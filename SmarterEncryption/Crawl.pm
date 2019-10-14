package SmarterEncryption::Crawl;

use Exporter::Shiny qw'
    aggregate_crawl_session
    check_ssl_cert
    dupe_link
    urls_by_path
';

use IO::Socket::SSL;
use IO::Socket::SSL::Utils 'CERT_asHash';
use Cpanel::JSON::XS 'encode_json';
use List::Util 'sum';
use URI;
use List::AllUtils qw'each_arrayref';
use Domain::PublicSuffix;

use strict;
use warnings;
no warnings 'uninitialized';
use feature 'state';

my $SSL_TIMEOUT = 5;
my $DEBUG = 0;

# Fields we want to convert to int if null
my @CONVERT_TO_INT = qw'
    https
    http_s
    https_errs
    http
    unknown
    autoupgrade
    mixed_requests
    max_ss_diff
    redirects
';

sub screenshot_threshold { 0.05 }
# Number of URLs checked for each domain per run.
sub urls_per_domain { 10 }

sub check_ssl_cert {
    my $host = shift;

    my ($issuer, $not_before, $not_after, $host_valid, $err);

    if(my $iossl = IO::Socket::SSL->new(
        PeerHost => $host,
        PeerPort => 'https',
        SSL_hostname => $host,
        Timeout => $SSL_TIMEOUT,
    )){
        $host_valid = $iossl->verify_hostname($host, 'http') || 0;
        my $c = $iossl->peer_certificate;
        my $cert = CERT_asHash($c);
        $issuer = $cert->{issuer}{organizationName};
        $not_before = gmtime($cert->{not_before}) . ' UTC';
        $not_after = gmtime($cert->{not_after}) . ' UTC';
    }
    else{
        my $sys_err = $!;
        $err = $SSL_ERROR;
        if($sys_err){ $err .= ": $sys_err"; }
    }

    return [$issuer, $not_before, $not_after, $host_valid, $err];
}

sub aggregate_crawl_session {
    my ($domain, $session) = @_;

    state $dps = Domain::PublicSuffix->new;
    my $root_domain = $dps->get_root_domain($domain);

    my %domain_stats = (is_redirect => 0);
    my %redirects;
    for my $comparison (@$session){
        my ($http_request_uri,
            $http_response,
            $https_request_uri,
            $https_response,
            $autoupgrade,
            $mixed,
            $screenshot_diff,
            $id
        ) = @$comparison{qw'
            http_request_uri
            http_response
            https_request_uri
            https_response
            autoupgrade
            mixed
            ss_diff
            id
        '};


        my $http_valid = $http_request_uri =~ /^http:/i;
        my $https_valid = $https_request_uri =~ /^https:/i;

        my $redirect;
        if($https_valid){
            if(my $host = eval { URI->new($https_request_uri)->host }){
                if($host ne $domain){
                    my $host_root_domain = $dps->get_root_domain($host);
                    if($root_domain eq $host_root_domain){
                        ++$domain_stats{redirects}{$host};
                        unless(exists $redirects{$host}){
                            $redirects{$host} = {is_redirect => 1};
                        }
                        $redirect = $redirects{$host};
                    }
                }
            }
        }

        ++$domain_stats{requests};
        $redirect && ++$redirect->{requests};

        $domain_stats{max_id} = $id if $domain_stats{max_id} < $id;
        $redirect->{max_id} = $id if $redirect && ($redirect->{max_id} < $id);

        if($autoupgrade){
            ++$domain_stats{autoupgrade};
            $redirect && ++$redirect->{autoupgrade};
        }

        if($mixed){
            ++$domain_stats{mixed_requests};
            $redirect && ++$redirect->{mixed_requests};
        }

        if(defined($screenshot_diff)){
            $domain_stats{max_ss_diff} = $screenshot_diff if $domain_stats{max_ss_diff} < $screenshot_diff;
            $redirect->{max_ss_diff} = $screenshot_diff if $redirect && ($redirect->{max_ss_diff} < $screenshot_diff)
        }

        my $http_s_same_response = $http_response == $https_response;
        my $http_response_good = $http_valid && ( ($http_response == 200) || $http_s_same_response );
        my $https_response_good = $https_valid && ( ($https_response == 200) || $http_s_same_response);

        if($https_response_good){
            if($http_response_good){
                ++$domain_stats{http_s};
                $redirect && ++$redirect->{http_s};
            }
            else{
                ++$domain_stats{https};
                $redirect && ++$redirect->{https};
            }

            if($https_response =~ /^[45]/){
                ++$domain_stats{https_errs};
                $redirect && ++$redirect->{https_errs};
            }
        }
        elsif($http_response_good){
            ++$domain_stats{http};
            $redirect && ++$redirect->{http};
        }
        else{
            ++$domain_stats{unknown};
            $redirect && ++$redirect->{unknown};
        }
    }

    my %aggs;
    if(my $hosts = delete $domain_stats{redirects}){
        $domain_stats{redirects} = sum values(%$hosts);
        $domain_stats{redirect_hosts} = encode_json($hosts);

        while(my ($host, $agg) = each %redirects){
            null_to_int($agg);
            $aggs{$host} = $agg;
        }
    }

    null_to_int(\%domain_stats);
    $aggs{$domain} = \%domain_stats;

    return \%aggs;
}

sub null_to_int {
    my $h = shift;
    $h->{$_} += 0 for @CONVERT_TO_INT;
}

sub urls_by_path {
    my ($urls, $rr, $url_limit) = @_;

    my %links;
    for my $url (@$urls){
        eval {
            my @segs = URI->new($url)->path_segments;
            push @{$links{$segs[1]}}, $url;
        };
    }

    my @sorted_paths = sort {@{$links{$b}} <=> @{$links{$a}}} keys %links;

    my @urls_by_path;

    my $paths = each_arrayref @links{@sorted_paths};
    CLICK_GROUP: while(my @urls = $paths->()){
        for my $url (@urls){
            next unless $url;
            last CLICK_GROUP unless @urls_by_path < $url_limit;
            next unless $rr->allowed($url);
            push @urls_by_path, $url;
        }
    }

    @$urls = @urls_by_path;
}


sub dupe_link {
    my ($url, $urls) = @_;

    $url =~ s{^https:}{http:}i;

    for (@$urls){
        my $u = $_ =~ s{^https:}{http:}ir;
        return 1 if URI::eq($u, $url);
    }

    0;
}

1;
