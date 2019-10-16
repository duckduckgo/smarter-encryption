# Contributing guidelines

# Reporting bugs

1. First check to see if the bug has not already been [reported](https://github.com/duckduckgo/smarter-encryption/issues).
2. Create a bug report [issue](https://github.com/duckduckgo/smarter-encryption/issues/new?template=bug_report.md).

# Feature requests

There are two ways to submit feedback:
1. You can send anonymous feedback using the "Send feedback" link on the extension's options page.
2. You can submit your request as an [issue](https://github.com/duckduckgo/duckduckgo-privacy-extension/issues/new?template=feature_request.md). First check to see if the feature has not already been [suggested](https://github.com/duckduckgo/duckduckgo-privacy-extension/issues).

# Development

## New features

Right now all new feature development is handled internally.

## Bug fixes

Most bug fixes are handled internally, but we will except pull requests for bug fixes if you first:
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

4. If you have a source of URLs you would like to be crawled for a host they can be added to the `full_urls` table:
```sql
insert into full_urls (host, url) values ('duckduckgo.com', 'https://duckduckgo.com/?q=privacy'), ...
```
The crawler will attempt to get URLs from the home page if none are available in this table.

### Running the crawler

1. The crawler can be run as follows:
```sh
perl -Mlib=/path/to/smarter-encryption https_crawl.pl -c /path/to/config.yml
```
2. Add a host to be crawled to the `https_queue` table:
```sql
insert into https_queue (domain) values ('duckduckgo.com');
```

### Checking the results

1. The individual HTTP and HTTPs comparisons for each URL crawled are stored in `https_crawl`:
```sql
select * from https_crawl where domain = 'duckduckgo.com' order by id desc limit 10;
```
The maximum URLs for the crawl session, i.e. `limit`, is set with [URLS_PER_SITE](config.yml.example#L49).

2. Aggregate session data for each host is stored in `https_crawl_aggregate`:
```sql
select * from https_crawl_aggregate where domain = 'duckduckgo.com';
```
There is also an associated view - `https_upgrade_metrics` - that further distills the session into percentages:
```sql
select * from https_upgrade_metrics where domain = 'duckduckgo.com';
```
