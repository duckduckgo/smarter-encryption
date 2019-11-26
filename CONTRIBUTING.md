# Contributing guidelines

* [Reporting bugs](#reporting-bugs)
* [Development](#development)
  * [New features](#new-features)
  * [Bug fixes](#bug-fixes)
* [Getting Started](#getting-started)
  * [Pre-Requisites](#pre-requisites)
  * [Setup](#setup)
  * [Running the crawler](#running-the-crawler)
  * [Checking the results](#checking-the-results)
* [Data Model](#data-model)
  * [full_urls](#full_urls)
  * [https_queue](#https_queue)
  * [https_crawl](#https_crawl)
  * [mixed_assets](#mixed_assets)
  * [https_response_headers](#https_response_headers)
  * [ssl_cert_info](#ssl_cert_info)
  * [https_crawl_aggregate](#https_crawl_aggregate)
  * [https_upgrade_metrics](#https_upgrade_metrics)
  * [domain_exceptions](#domain_exceptions)
  * [upgradeable_domains](#upgradeable_domains)

# Reporting bugs

1. First check to see if the bug has not already been [reported](https://github.com/duckduckgo/smarter-encryption/issues).
2. Create a bug report [issue](https://github.com/duckduckgo/smarter-encryption/issues/new?template=bug_report.md).

# Development

## New features

Right now all new feature development is handled internally.

## Bug fixes

Most bug fixes are handled internally, but we will accept pull requests for bug fixes if you first:
1. Create an issue describing the bug. see [Reporting bugs](CONTRIBUTING.md#reporting-bugs)
2. Get approval from DDG staff before working on it. Since most bug fixes and feature development are handled internally, we want to make sure that your work doesn't conflict with any current projects.

## Getting Started

### Pre-Requisites
- [PostgreSQL](https://www.postgresql.org/) database
- [PhantomJS 2.1.1](https://phantomjs.org/download.html)
- [Perl](https://www.perl.org/get.html)
- [compare](https://imagemagick.org/script/compare.php)
- [pkill](https://en.wikipedia.org/wiki/Pkill)
- Should run on many varieties of Linux/*BSD

### Setup

1. Install required Perl modules via cpanfile:
```sh
cpanm --installdeps .
```
2. Connect to PostgreSQL with psql and create the tables needed by the crawler:
```
\i sql/full_urls.sql
\i sql/https_crawl.sql
\i sql/mixed_assets.sql
etc.
```
3. Create a copy of the crawler configuration file:
```sh
cp config.yml.example config.yml
```
Edit the settings as necessary for your system.

4. If you have a source of URLs you would like to be crawled for a host they can be added to the [full_urls](#full_urls) table:
```sql
insert into full_urls (host, url) values ('duckduckgo.com', 'https://duckduckgo.com/?q=privacy'), ...
```
The crawler will attempt to get URLs from the home page even if none are available in this table.

### Running the crawler

1. Add hosts to be crawled to the [https_queue](#https_queue) table:
```sql
insert into https_queue (domain) values ('duckduckgo.com');
```

2. The crawler can be run as follows:
```sh
perl -Mlib=/path/to/smarter-encryption https_crawl.pl -c /path/to/config.yml
```

### Checking the results

1. The individual HTTP and HTTPs comparisons for each URL crawled are stored in [https_crawl](#https_crawl):
```sql
select * from https_crawl where domain = 'duckduckgo.com' order by id desc limit 10;
```
The maximum URLs for the crawl session, i.e. `limit`, is determined by [URLS_PER_SITE](config.yml.example#L49).

2. Aggregate session data for each host is stored in [https_crawl_aggregate](#https_crawl_aggregate):
```sql
select * from https_crawl_aggregate where domain = 'duckduckgo.com';
```
There is also an associated view - [https_upgrade_metrics](#https_upgrade_metrics) - that calculates some additional metrics:
```sql
select * from https_upgrade_metrics where domain = 'duckduckgo.com';
```

3. Additional information from the crawl can be found in:

  * [sss_cert_info](#ssl_cert_info)
  * [mixed_assets](#mixed_assets)
  * [https_response_headers](#https_response_headers)

4. Hosts can be selected based on various combinations of criteria directly from the above tables or by using the [upgradeable_domains](#upgradeable_domains) function.  

### Data Model

#### full_urls

Complete URLs for hosts that will be used in addition to those the crawler extracts from the home page.

| Column | Description | Type | Key |
| --- | --- | --- | --- |
| host | hostname | text |unique|
| url | Complete URL with scheme | text |unique|
| updated | When added to table | timestamp with time zone ||

#### https_queue

Domains to be crawled in rank order.  Multiple crawlers can access this concurrently.

| Column | Description | Type | Key |
| --- | --- | --- | --- |
| rank | Processing order | integer | primary |
|domain | Domain to be crawled | character varying(500) ||
|processing_host|Hostname of server processing domain|character varying(50)||
|worker_pid|Process ID of crawler handling domain|integer||
|reserved|When domain was selected for processing|timestamp with time zone||
|started|When processing of domain started|timestamp with time zone||
|finished|When processing of domain completed|timestamp with time zone||

#### https_crawl

Log table of HTTP and HTTPs comparisons made by the crawler.

| Column | Description | Type | Key |
| --- | --- | --- | --- |
| id | Comparison ID | bigint | unique |
|domain|Domain evaluated|text||
|http_request_uri|Resulting URI of HTTP request|text||
|http_response|HTTP status code for HTTP request|integer||
|http_requests|Total requests made, including child subrequests, for HTTP request|integer||
|http_size|Size of HTTP response (bytes)|integer||
|https_request_uri|Resulting URI of HTTPs request|text||
|https_response|HTTP status code for HTTPs request|integer||
|https_requests|Total requests made, including child subrequests, for HTTPs request|integer||
|https_size|Size of HTTPs response (bytes)|integer||
|timestamp|When inserted|timestamp with time zone||
|screenshot_diff|Percentage difference between HTTP and HTTPs screenshots after page load|real||
|autoupgrade|Whether HTTP request was redirected to HTTPs|boolean||
|mixed|Whether HTTPs request had HTTP child requests|boolean||

#### mixed_assets

HTTP child requests made for HTTPs.

| Column         | Description                                          | Type   | Key            |
| ---            | ---                                                  | ---    | ---            |
| https_crawl_id | https_crawl.id, only associated with https_* columns | bigint | unique/foreign |
| asset          | URI of HTTP subrequest made during HTTPs request     | text   | unique         |


#### https_response_headers

The response headers for HTTPs requests.

| Column         | Description                                          | Type   | Key            |
| ---            | ---                                                  | ---    | ---            |
| https_crawl_id | https_crawl.id, only associated with https_* columns | bigint | unique/foreign |
|response_headers|key/value of all HTTPs response headers|jsonb||


#### ssl_cert_info

SSL certificate information for domains crawled.

| Column         | Description                                          | Type   | Key            |
| ---            | ---                                                  | ---    | ---            |
| domain | Domain evaluated | text | primary |
|issuer|Issuer of SSL certificate|text||
|notbefore|Valid from timestamp|timestamp with time zone||
|notafter|Valid to timestamp|timestamp with time zone||
|host_valid|Whether the domain is covered by the SSL certificate|boolean||
|err|Connection err|text||
|updated|When last updated|timestamp with time zone||

#### https_crawl_aggregate

Aggregate of [https_crawl](#https_crawl) that creates latest crawl sessions based on domain.  Can also include domains that were redirected to and not directly crawled.

| Column         | Description                                          | Type   | Key            |
| ---            | ---                                                  | ---    | ---            |
| domain | Domain evaluated | text | primary |
|https|Comparisons where only HTTPs was supported|integer||
|http_and_https|Comparisons where HTTP and HTTPs were supported|integer||
|http|Comparisons where only HTTP was supported|integer||
|https_errs|Number of non-2xx HTTPs responses|integer||
|unknown|Comparisons where neither HTTP nor HTTPs responses were valid or the status codes differed|integer||
|autoupgrade|Comparisons where HTTP was redirected to HTTPs|integer||
|mixed_requests|HTTPs request that made HTTP calls|integer||
|max_screenshot_diff|Maximum percentage difference between HTTP and HTTPs screenshots|real||
|redirects|Number of HTTPs requests redirected to different host|integer||
|requests|Number of comparison requests actually made during the crawl session|integer||
|session_request_limit|The number of comparisons wanted for the session|integer||
|is_redirect|Whether the domain was actually crawled or is a redirect from another host in the table that was crawled|boolean||
|redirect_hosts|key/value pairs of hosts and the number of redirects to it|jsonb||
|updated|When last updated|timestamp with time zone||

#### https_upgrade_metrics

View of [https_crawl_aggregate](#https_crawl_aggregate) that calculates crawl session percentages for easier selection based on cutoffs.

| Column         | Description                                          | Type   | Key            |
| ---            | ---                                                  | ---    | ---            |
| domain | Domain evaluated | text | |
| unknown_pct | Percentage of unknown|real||
| combined_pct | Percentage that supported HTTPs|real||
| https_err_rate | Percentage unknown|real||
| max_screenshot_diff | https_crawl_aggregate.max_screenshot_diff|real||
| mixed_ok | Whether HTTPs requests contained mixed content requests|boolean||
| autoupgrade_pct|Percentage of autoupgrade|real||

#### domain_exceptions

For manually excluding domains that may otherwise pass specific upgrade criteria given to [upgradeable_domains](#upgradeable_domains).

| Column | Description       | Type | Key     |
| ---    | ---               | ---  | ---     |
| domain | Domain to exclude | text | primary |
| comment | Reason for exclusion | text ||
|updated|When added|timestamp with time zone||

#### upgradeable_domains

Function to select domains based on a variety of criteria.

| Parameter | Description       | Type | Source     |
| ---    | ---               | ---  | ---     |
|autoupgrade_min|Minimum autoupgrade percentage|real|[https_upgrade_metrics](#https_upgrade_metrics)|
|combined_min|Minimum percentage of HTTPs responses|real|[https_upgrade_metrics](#https_upgrade_metrics)|
|screenshot_diff_max|Maximum observed screenshot diff allowed|real|[https_upgrade_metrics](#https_upgrade_metrics)|
|mixed_ok|Whether to allow domains that had mixed content|boolean|[https_upgrade_metrics](#https_upgrade_metrics)|
|max_err_rate|Maximum https_err_rate|real|[https_upgrade_metrics](#https_upgrade_metrics)|
|unknown_max|Maximum unknown comparisons|real|[https_upgrade_metrics](#https_upgrade_metrics)|
|ssl_cert_buffer|SSL certificate must be valid until this timestamp|timestamp with time zone|[ssl_cert_info](#ssl_cert_info)|
|exclude_issuers|Array of SSL cert issuers to exclude|text array|[ssl_cert_info](#ssl_cert_info)|

In addtion to the above parameters, the function enforces several other conditions:

1. Domain must not be in [domain_exceptions](#domain_exceptions)
2. From values in [ssl_cert_info](#ssl_cert_info):
   1. No err
   2. The domain, or host, must be valid for the certificate.
   3. Valid from/to and the issuer must not be null
