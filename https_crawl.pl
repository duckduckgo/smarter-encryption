#!/usr/bin/env perl

use LWP::UserAgent;
use WWW::Mechanize;
use POE::Kernel { loop => 'POE::XS::Loop::Poll' };
use POE qw(Wheel::Run Filter::Reference);
use DBI;
use Sys::Hostname 'hostname';
use Cpanel::JSON::XS qw'decode_json encode_json';
use URI;
use File::Copy::Recursive qw'pathmk pathrmdir';
use WWW::RobotRules;
use IPC::Run;
use YAML::XS 'LoadFile';
use List::AllUtils 'each_arrayref';
use SmarterEncryption::Crawl qw'
    aggregate_crawl_session
    check_ssl_cert
    dupe_link
    urls_by_path
';
use Module::Load::Conditional 'can_load';

use feature 'state';
use strict;
use warnings;
no warnings 'uninitialized';

my $DDG_INTERNAL;
if(can_load(modules => {'DDG::Util::HTTPS2' => undef})){
    DDG::Util::HTTPS2->import(qw'add_stat backfill_urls');
    $DDG_INTERNAL = 1;
}

my $HOST = hostname();

# Crawler Config
my %CC;

# Derived config values
my ($MAX_CONCURRENT_CRAWLERS, $PHANTOM_TIMEOUT, $HOMEPAGE_LINKS_MAX); 

POE::Session->create(
    inline_states => {
        _start         => \&_start,
        _stop          => \&normal_cleanup,
        crawl          => \&start_crawlers,
        crawler_done   => \&crawler_done,
        crawler_debug  => \&crawler_debug,
        sig_child      => \&sig_child,
        shutdown       => \&shutdown_now,
        prune_tmp_dirs => \&prune_tmp_dirs
    }
);

POE::Kernel->run;
exit;

sub _start {
    my ($k, $h) = @_[KERNEL, HEAP];

    parse_argv();

    unless($MAX_CONCURRENT_CRAWLERS){
        $MAX_CONCURRENT_CRAWLERS = `nproc` * $CC{CRAWLERS_PER_CPU};
    }

    $PHANTOM_TIMEOUT = $CC{HEADLESS_ALARM} * 1000; # in ms
    $HOMEPAGE_LINKS_MAX = sprintf '%d', $CC{HOMEPAGE_LINK_PCT} * $CC{URLS_PER_SITE};

    my $TMP_DIR = $CC{TMP_DIR};
    unless(-d $TMP_DIR){
        $CC{VERBOSE} && warn "Creating temp dir $TMP_DIR\n";
        pathmk($TMP_DIR) or die "Failed to create tmp dir $TMP_DIR: $!";
    }

    # clean up leftover junk for forced shutdown
    while(<$TMP_DIR/$CC{CRAWLER_TMP_PREFIX}*>){
        chomp;
        pathrmdir($_) or warn "Failed to remove old crawler tmp dir $_: $!";
    }

    $k->sig($_ => 'shutdown') for qw{TERM INT};

    $k->yield('crawl');
}

sub shutdown_now {
    $_[KERNEL]->sig_handled;

    # Kill crawlers
    $_->kill() for values %{$_[HEAP]->{crawlers}};

    # Make unfinished tasks available in the queue
    my $db = prep_db('queue');
    $db->{reset_unfinished_tasks}->execute;

    normal_cleanup();

    exit 1;
}

sub normal_cleanup {
    # remove tmp dir
    pathrmdir($CC{TMP_DIR}) if -d $CC{TMP_DIR};
}

sub start_crawlers{
    my ($k, $h) = @_[KERNEL, HEAP];

    my $db = prep_db('queue');

    my $reserve_tasks = $db->{reserve_tasks};
    while(keys %{$h->{crawlers}} < $MAX_CONCURRENT_CRAWLERS){

        $reserve_tasks->execute();
        if(my @ranks = sort map { $_->[0] } @{$reserve_tasks->fetchall_arrayref}){

            my $c = POE::Wheel::Run->new(
                Program      => \&crawl_sites,
                ProgramArgs  => [\@ranks],
                CloseOnCall  => 1,
                NoSetSid     => 1,
                StderrEvent  => 'crawler_debug',
                CloseEvent   => 'crawler_done',
                StdinFilter  => POE::Filter::Reference->new,
                StderrFilter => POE::Filter::Line->new
            );
            $h->{crawlers}{$c->ID} = $c;
            $k->sig_child($c->PID, 'sig_child');
        }
        else{
            $CC{POLL} && $k->delay(crawl => $CC{POLL});
            last;
        }
    }
}

sub crawl_sites{
    my ($ranks) = @_;

    my $VERBOSE = $CC{VERBOSE};
    my $db = prep_db('crawl');

    my $crawler_tmp_dir = "$CC{TMP_DIR}/$CC{CRAWLER_TMP_PREFIX}$$";
    my $rm_tmp = pathmk($crawler_tmp_dir);

    my @urls_by_domain;
    for(my $i = 0;$i < @$ranks;++$i){
        my $rank = $ranks->[$i];

        my $domain;
        eval {
            $db->{start_task}->execute($$, $rank);
            $domain = $db->{start_task}->fetchall_arrayref->[0][0];
        }
        or do {
            warn "Failed to start task for rank $rank: $@";
            next;
        };

        eval {
            $domain = URI->new("https://$domain/")->host;
            1;
        }
        or do {
            warn "Failed to filter domain $domain: $@";
            next;
        };

        $VERBOSE && warn "checking domain $domain\n";
        my $urls = get_urls_for_domain($domain, $db);
        my @pairs;
        for my $url (@$urls){
            push @pairs, [$domain, $url];
        }
        push @urls_by_domain, \@pairs if @pairs;
    }

    my $ranks_str = '{' . join(',', @$ranks) . '}';

    my $ea = each_arrayref @urls_by_domain;

    my (%ssl_cert_checked, %domain_render_delay, %sessions);
    while(my @urls = $ea->()){
        for my $u (@urls){
            next unless $u;
            my ($domain, $url) = @$u;
            next unless $url =~ /^http/i;

            # for the command-line
            $url =~ s/'/%27/g;

            my ($http_url) = $url =~ s/^https:/http:/ri;
            my ($https_url) = $url =~ s/^http:/https:/ri;

            my $http_ss = $crawler_tmp_dir . '/http.' . $domain . '.png';

            unless($ssl_cert_checked{$domain}){
                my $ssl = check_ssl_cert($domain);
                eval {
                    $db->{insert_ssl}->execute($domain, @$ssl);
                    ++$ssl_cert_checked{$domain};
                }
                or do {
                    warn "Failed to insert ssl info for $domain: $@";
                };
            }

            my %comparison;
            # We will compare a URL twice max:
            # 1. Compare HTTP vs. HTTPS
            # 2. Redo if the screenshot is a above the threshold to check for rendering problems
            SCREENSHOT_RETRY: for (0..$CC{SCREENSHOT_RETRIES}){
                my $redo_comparison = 0;

                my %stats = (domain => $domain);
                check_site(\%stats, $http_url, $http_ss, $domain_render_delay{$domain}, $crawler_tmp_dir);
                # the idea behind screenshots is:
                # 1. Do for HTTP automatically so we don't have to make another request if it works
                # 2. Do for HTTPS if HTTP worked and wasn't autoupgraded
                # 3. If HTTPS worked and didn't downgrade, compare them
                my $https_ss;
                if( (-e $http_ss) && ($stats{http_request_uri} =~ /^http:/i) && ($stats{http_response} == 200)){
                    $https_ss = $crawler_tmp_dir . '/https.' . $domain . '.png';
                }

                HTTPS_RETRY: for my $https_attempt (0..$CC{HTTPS_RETRIES}){
                    my $redo_https;
                    check_site(\%stats, $https_url, $https_ss, $domain_render_delay{$domain}, $crawler_tmp_dir);
                    if( ($stats{https_request_uri} =~ /^https:/i) && ($stats{https_response} == 200)){
                        if($https_ss && (-e $https_ss)){
                            my $out = `$CC{COMPARE} -metric mae $http_ss $https_ss /dev/null 2>&1`;

                            if(my ($diff) = $out =~ /\(([\d\.e\-]+)\)/){
                                if($CC{SCREENSHOT_THRESHOLD} < $diff){
                                    # Only need to redo on the first failure. After that, the delay
                                    # will have already been increased by a previous URL
                                    unless($domain_render_delay{$domain} == $CC{PHANTOM_RENDER_DELAY}){
                                        $domain_render_delay{$domain} = $CC{PHANTOM_RENDER_DELAY};
                                        $redo_comparison = 1;
                                        $VERBOSE && warn "redoing $http_url (diff: $diff)\n";
                                    }
                                }
                                $stats{ss_diff} = $diff;
                            }
                            else{
                                warn "Failed to extract compare diff betweeen $http_ss and $https_ss from $out\n";
                            }
                            unlink $_ for $http_ss, $https_ss;
                        }

                        if($DDG_INTERNAL && $https_attempt){
                            add_stat(qw'increment smarter_encryption.crawl.https_retries.success');
                        }
                    }
                    elsif($DDG_INTERNAL && $https_attempt){
                        add_stat(qw'increment smarter_encryption.crawl.https_retries.failure');
                    }
                    elsif( ($stats{https_request_uri} !~ /^http:/) && ($stats{http_response} != $stats{https_response})){
                        $redo_https = 1;
                        $VERBOSE && warn "Redoing HTTPS request for $domain: $https_url\n";
                    }

                    last HTTPS_RETRY unless $redo_https;
                }

                # Most should exit here
                unless($redo_comparison){
                    %comparison = %stats;
                    last;
                }
            }

            unless($db->{con}->ping){
                $VERBOSE && warn "Reconnecting to DB before inserting comparison";
                $db = prep_db('crawl');
            }

            if(my $host = eval { URI->new($comparison{https_request_uri})->host}){
                unless($ssl_cert_checked{$host}){
                    my $ssl = check_ssl_cert($host);
                    eval {
                        $db->{insert_ssl}->execute($host, @$ssl);
                        ++$ssl_cert_checked{$host};
                    }
                    or do {
                        warn "Failed to insert ssl info for $host: $@";
                    };
                }
            }

            if($comparison{http_request_uri} || $comparison{https_request_uri}){
                my $log_id;
                eval {
                    $db->{insert_domain}->execute(@comparison{qw'
                        domain
                        http_request_uri
                        http_response
                        http_requests
                        http_size
                        https_request_uri
                        https_response
                        https_requests
                        https_size
                        autoupgrade
                        mixed
                        ss_diff'}
                    );
                    $log_id = $db->{insert_domain}->fetch()->[0];
                }
                or do {
                   $VERBOSE && warn "Failed to insert request for $domain: $@";
                };

                if($log_id){
                    if(my $hdrs = delete $comparison{https_response_headers}){
                        eval {
                            $db->{insert_headers}->execute($log_id, $hdrs);
                        }
                        or do {
                            $VERBOSE && warn "Failed to insert response headers for $domain ($log_id): $@";
                        };
                    }

                    if(my $mixed_reqs = delete $comparison{mixed_children}){
                        for my $m (keys %$mixed_reqs){
                            eval{
                                $db->{insert_mixed}->execute($log_id, $m);
                                1;
                            }
                            or do {
                                $VERBOSE && warn "Failed to insert mixed request for $domain: $@";
                            };
                        }
                    }
                    $comparison{id} = $log_id;
                    push @{$sessions{$domain}}, \%comparison;
                }
            }
        }
    }

    unless($db->{con}->ping){
        $VERBOSE && warn "Reconnecting to DB before updating aggregate data";
        $db = prep_db('crawl');
    }

    while(my ($domain, $session) = each %sessions){
        my $aggregates = aggregate_crawl_session($domain, $session);
        while(my ($host, $agg) = each %$aggregates){
            eval {
                $db->{upsert_aggregate}->execute(
                    $host, @$agg{qw'
                        https
                        http_s
                        https_errs
                        http
                        unknown
                        autoupgrade
                        mixed_requests
                        max_ss_diff
                        redirects
                        max_id
                        requests
                        is_redirect
                        redirect_hosts'
                    }
                );
                1;
            }
            or do {
                warn "Failed to upsert aggregate for $host: $@";
            };
        }
    }

    eval {
        $db->{finish_tasks}->execute($ranks_str);
        1;
    }
    or do {
        warn "Failed to finish tasks for ranks ($ranks_str): $@";
    };

    system "$CC{PKILL} -9 -f '$crawler_tmp_dir '";
    pathrmdir($crawler_tmp_dir) if $rm_tmp;
}

sub prep_db {
    my $target = shift;

    my %db;

    my $con = get_con();

    if($target eq 'queue'){
        $db{reserve_tasks} = $con->prepare("
            update https_queue
                set processing_host = '$HOST',
                    reserved = now()
            where rank in (
                select rank from https_queue
                    where processing_host is null
                    order by rank
                    limit $CC{SITES_PER_CRAWLER}
                    for update skip locked
            )
            returning rank
        ");
        my $reset_tasks = "
            update https_queue
                set processing_host = null,
                worker_pid = null,
                reserved = null,
                started = null
            where
                processing_host = '$HOST' and
                finished is null";
        $db{reset_unfinished_tasks} = $con->prepare($reset_tasks);
        $db{reset_unfinished_worker_tasks} = $con->prepare($reset_tasks .
            ' and worker_pid = ?'
        );
    }
    elsif($target eq 'crawl'){
        $db{start_task} = $con->prepare('update https_queue set worker_pid = ?, started = now() where rank = ? returning domain');
        $db{select_urls} = $con->prepare('select url from full_urls where host = ?');
        $db{insert_domain} = $con->prepare('
            insert into https_crawl
              (domain, http_request_uri, http_response, http_requests, http_size, https_request_uri, https_response, https_requests, https_size, autoupgrade, mixed, screenshot_diff)
              values (?,?,?,?,?,?,?,?,?,?,?,?) returning id
        ');
        $db{insert_mixed} = $con->prepare('insert into mixed_assets (https_crawl_id, asset) values (?,?)');
        $db{insert_headers} = $con->prepare('insert into https_response_headers (https_crawl_id, response_headers) values (?,?)');
        $db{finish_tasks} = $con->prepare('update https_queue set finished = now() where rank = ANY(?::integer[])');
        $db{insert_ssl} = $con->prepare('
            insert into ssl_cert_info (domain, issuer, notBefore, notAfter, host_valid, err) values (?,?,?,?,?,?)
            on conflict (domain) do update set
            issuer = EXCLUDED.issuer,
            notBefore = EXCLUDED.notBefore,
            notAfter = EXCLUDED.notAfter,
            host_valid = EXCLUDED.host_valid,
            err = EXCLUDED.err,
            updated = now()
        ');
        # Note where clause:
        # 1. Non-redirects update any, including changing a redirect to a non-redirect
        # 2. Redirects update other redirects
        $db{upsert_aggregate} = $con->prepare("
            insert into https_crawl_aggregate (
                domain,
                https,
                http_and_https,
                https_errs, http,
                unknown,
                autoupgrade,
                mixed_requests,
                max_screenshot_diff,
                redirects,
                max_https_crawl_id,
                requests,
                is_redirect,
                redirect_hosts,
                session_request_limit)
                values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,$CC{URLS_PER_SITE})
            on conflict (domain) do update set (
                https,
                http_and_https,
                https_errs,
                http,
                unknown,
                autoupgrade,
                mixed_requests,
                max_screenshot_diff,
                redirects,
                max_https_crawl_id,
                requests,
                is_redirect,
                redirect_hosts,
                session_request_limit
            ) = (
                EXCLUDED.https,
                EXCLUDED.http_and_https,
                EXCLUDED.https_errs,
                EXCLUDED.http,
                EXCLUDED.unknown,
                EXCLUDED.autoupgrade,
                EXCLUDED.mixed_requests,
                EXCLUDED.max_screenshot_diff,
                EXCLUDED.redirects,
                EXCLUDED.max_https_crawl_id,
                EXCLUDED.requests,
                EXCLUDED.is_redirect,
                EXCLUDED.redirect_hosts,
                EXCLUDED.session_request_limit)
            where
                EXCLUDED.is_redirect = false or
                https_crawl_aggregate.is_redirect = true
        ");
    }

    $db{con} = $con;
    return \%db;
}

# Strategy behind url selection:
# 1. Fill queue with homepage and click urls sort by top-level path
#    prevalence
# 2. If necessary, get backfill_urls
sub get_urls_for_domain {
    my ($domain, $db) = @_;

    state $rr = WWW::RobotRules->new($CC{UA});
    state $mech = get_ua('mech');
    state $VERBOSE = $CC{VERBOSE};

    # Get latest robot rules for domain
    my $res = $mech->get("http://$domain/robots.txt");
    if($res->is_success){
        # the uri may be different than what we requested
        my @doms = ($domain);
        my $uri = $res->request->uri;
        if(my $host = eval { URI->new($uri)->host }){
            push @doms, $host if $host ne $domain;
        }
        my $robots_txt = $res->decoded_content;

        # Add the rules for the:
        # 1. The domain and redirect host if different
        # 2. HTTP/HTTPS for each
        # yes, http and https could be different
        for my $d (@doms){
            for my $p (qw(http https)){
                $rr->parse("$p://$d/", $robots_txt);
            }
        }
    }

    my @urls;
    my $homepage = 'http://' . $domain . '/';

    $res = $mech->get($homepage);

    if($res->is_success){
        # the uri may be different than what we requested
        my $uri = $res->request->uri;
        if(my $host = eval { URI->new($uri)->host }){
            # all links with the same host
            my @homepage_links;
            if(my $l = $mech->find_all_links(url_abs_regex => qr{//\Q$host\E/})){
                @homepage_links = @$l;
            }

            for my $l (@homepage_links){
                my $abs_url = $l->url_abs;
                $abs_url = "$abs_url";
                next if dupe_link($abs_url, \@urls);
                push @urls, $abs_url;
            }
        }
    }
    else {
        $VERBOSE && warn "Failed to get homepage links for $domain: " . $res->status_line;
    }

    eval {
        my $select_urls = $db->{select_urls};
        $select_urls->execute($domain);
        while(my $r = $select_urls->fetchrow_arrayref){
            my $url = $r->[0];
            next if dupe_link($url, \@urls);
            push @urls, $url;
        }
        1;
    }
    or do {
        $VERBOSE && warn "Failed to get click urls for $domain: $@";
    };

    state $URLS_PER_SITE = $CC{URLS_PER_SITE};

    urls_by_path(\@urls, $rr, $URLS_PER_SITE);

    if($DDG_INTERNAL && (@urls < $URLS_PER_SITE)){
        backfill_urls($domain, \@urls, $rr, $db, $mech, $URLS_PER_SITE, $VERBOSE);
    }

    # Add home by default since it often behaves differently
    unless(dupe_link($homepage, \@urls)){
        if(@urls < $URLS_PER_SITE){
            push @urls, $homepage;
        }
        else{
            splice(@urls, -1, 1, $homepage);
        }
    }

    return \@urls;
}

sub prune_tmp_dirs {
    my $h = $_[HEAP];

    return unless exists $h->{crawler_tmp_dirs};

    my ($TMP_DIR, $CRAWLER_TMP_PREFIX) = @CC{qw'TMP_DIR CRAWLER_TMP_PREFIX'};
    for my $pid (keys %{$h->{crawler_tmp_dirs}}){
        my $crawler_tmp_dir = "$TMP_DIR/$CRAWLER_TMP_PREFIX$pid";
        if(-d $crawler_tmp_dir){
            next unless pathrmdir($crawler_tmp_dir);
        }
        delete $h->{crawler_tmp_dirs}{$pid};
    }
}

sub check_site {
    my ($stats, $site, $screenshot, $delay, $crawler_tmp_dir) = @_;

    if(my ($request_scheme) = $site =~ /^(https?):/i){
        $request_scheme = lc $request_scheme;

        eval{
            @ENV{qw(PHANTOM_RENDER_DELAY PHANTOM_UA PHANTOM_TIMEOUT)} =
                ($delay, "'$CC{UA}'", $PHANTOM_TIMEOUT);

            my $out;
            my @cmd = (
                $CC{PHANTOMJS},
                "--local-storage-path=$crawler_tmp_dir", "--offline-storage-path=$crawler_tmp_dir",
                $CC{NETSNIFF_SS}, $site);
            push @cmd, $screenshot if $screenshot;

            IPC::Run::run \@cmd,  \undef, \$out,
                IPC::Run::timeout($CC{HEADLESS_ALARM}, exception => "$site timed out after $CC{HEADLESS_ALARM} seconds");
            die "PHANTOMJS $out" if $out =~ /^FAIL/;

            # Can have error messages at the end so have to extract the json
            my ($j) = $out =~ /^(\{\s+"log".+\})/ms;
            my $m = decode_json($j)->{log};

            my ($main_request_scheme, $check_mixed);
            for my $e (@{$m->{entries}}){
                my $response_status = $e->{response}{status};
                # netsniff records the redirects to https for some sites
                next if $response_status =~ /^3/;
                my $url = $e->{request}{url};
                next unless my ($scheme) = $url =~ /^(https?):/i;
                $scheme = lc $scheme;

                if($check_mixed && ($scheme eq 'http')){
                    # Absolute links.  Even if the same host as parent, browsers will mark
                    # this as mixed and the extension can't upgrade them
                    $stats->{mixed_children}{$url} = 1;
                }

                unless($main_request_scheme){
                    $stats->{"${request_scheme}_request_uri"} = $url;
                    $stats->{"${request_scheme}_response"} = $response_status;
                    if($request_scheme eq 'http'){
                        $stats->{autoupgrade} = $scheme eq 'https' ? 1 : 0;
                    }
                    elsif($scheme eq 'https'){
                        $check_mixed = lc URI->new($url)->host;
                        my $hdrs = delete $e->{response}{headers};
                        my %response_headers;
                        # We don't want to store an array of one-key hashes.
                        for my $h (@$hdrs){
                            my ($name, $value) = @$h{qw(name value)};
                            if(exists $response_headers{$name}){
                                # https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.2
                                $response_headers{$name} .= ",$value";
                            }
                            else{
                                $response_headers{$name} = $value;
                            }
                        }
                        $stats->{https_response_headers} = encode_json(\%response_headers);
                    }
                    $main_request_scheme = $scheme;
                }

                $stats->{"${request_scheme}_size"} += $e->{response}{bodySize};
                ++$stats->{"${request_scheme}_requests"};

            }

            if($check_mixed){
                $stats->{mixed} = exists $stats->{mixed_children} ? 1 : 0;
            }
            1;
        }
        or do {
            warn "check_site error: $@ ($site)";
            system "$CC{PKILL} -9 -f '$crawler_tmp_dir '" if $crawler_tmp_dir =~ /\S/;
        };
    }
}

sub crawler_done{
    my ($k, $h, $id) = @_[KERNEL, HEAP, ARG0];

    state $VERBOSE = $CC{VERBOSE};
    $VERBOSE && warn "deleting crawler $id\n";
    my $c = delete $h->{crawlers}{$id};

    # see if any of its domains were left unfinished
    my $pid = $c->PID;
    my $db = prep_db('queue');
    my $unfinished = $db->{reset_unfinished_worker_tasks}->execute($pid);
    if($unfinished > 0){
        $VERBOSE && warn "Reset $unfinished tasks for crawler with pid $pid\n";
    }

    # Check and clean up tmp dirs for hung crawlers
    $h->{crawler_tmp_dirs}{$pid} = 1;
    $k->yield('prune_tmp_dirs');

    $k->yield('crawl');
}

sub crawler_debug{
    my $msg = $_[ARG0];

    $CC{VERBOSE} && warn 'crawler debug: ' . $msg. "\n";
}

sub sig_child {
    warn 'Got signal from pid ' . $_[ARG1] . ', exit status: ' . $_[ARG2] if $_[ARG2];
    $_[KERNEL]->sig_handled;
}

sub get_ua {
    my $type = shift;

    my $ua = $type eq 'mech' ?
        WWW::Mechanize->new(
            onerror => undef, # We'll check these ourselves so we don't have to catch die in eval
            quiet => 1
        ) 
        :
        LWP::UserAgent->new();

    $ua->agent($CC{UA});
    $ua->timeout(10);
    return $ua;
}

sub get_con {

    $ENV{PGDATABASE} = $CC{DB}   if exists $CC{DB};
    $ENV{PGHOST}     = $CC{HOST} if exists $CC{HOST};
    $ENV{PGPORT}     = $CC{PORT} if exists $CC{PORT};
    $ENV{PGUSER}     = $CC{USER} if exists $CC{USER};
    $ENV{PGPASSWORD} = $CC{PASS} if exists $CC{PASS};

    return DBI->connect('dbi:Pg:', '', '', {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
    });
}

sub parse_argv {
    my $usage = <<ENDOFUSAGE;

     *********************************************************************
       USAGE: https_crawl.pl -c /path/to/config.yml [-h]

       -c: Path to YAML config file
       -h: Print this help

    ***********************************************************************

ENDOFUSAGE

    my $config_file_specified;
    for(my $i = 0;$i < @ARGV;$i++) {
        if($ARGV[$i] =~ /^-c$/i ){
            %CC = %{LoadFile($ARGV[++$i])};
            $config_file_specified = 1;
        }
        elsif($ARGV[$i] =~ /^-h$/i ){ die "$usage\n" }
    }

    die "Config file required\n\n$usage\n" unless $config_file_specified;
}
