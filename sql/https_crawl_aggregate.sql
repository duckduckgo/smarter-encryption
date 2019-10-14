--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.9
-- Dumped by pg_dump version 9.5.9

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: https_crawl_aggregate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE https_crawl_aggregate (
    domain text NOT NULL,
    https integer DEFAULT 0 NOT NULL,
    http_and_https integer DEFAULT 0 NOT NULL,
    https_errs integer DEFAULT 0 NOT NULL,
    http integer DEFAULT 0 NOT NULL,
    unknown integer DEFAULT 0 NOT NULL,
    autoupgrade integer DEFAULT 0 NOT NULL,
    mixed_requests integer DEFAULT 0 NOT NULL,
    max_screenshot_diff real DEFAULT 0 NOT NULL,
    redirects integer DEFAULT 0 NOT NULL,
    requests integer NOT NULL,
    session_request_limit integer NOT NULL,
    is_redirect boolean DEFAULT false NOT NULL,
    max_https_crawl_id bigint NOT NULL,
    redirect_hosts jsonb
);


--
-- Name: https_upgrade_metrics; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE VIEW https_upgrade_metrics AS
 SELECT https_crawl_aggregate.domain,
    ((https_crawl_aggregate.unknown)::real / (https_crawl_aggregate.requests)::real) AS unknown_pct,
    ((((https_crawl_aggregate.https + https_crawl_aggregate.http_and_https)))::double precision / (https_crawl_aggregate.requests)::real) AS combined_pct,
    coalesce(https_crawl_aggregate.https_errs::real/nullif( (https_crawl_aggregate.https + https_crawl_aggregate.http_and_https), 0), 0)::real as https_err_rate,
    https_crawl_aggregate.max_screenshot_diff,
    ((https_crawl_aggregate.mixed_requests = 0) OR (https_crawl_aggregate.autoupgrade = https_crawl_aggregate.requests)) AS mixed_ok,
    ((https_crawl_aggregate.autoupgrade)::double precision / (https_crawl_aggregate.requests)::real) AS autoupgrade_pct
   FROM https_crawl_aggregate;


--
-- Name: https_crawl_aggregate_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY https_crawl_aggregate
    ADD CONSTRAINT https_crawl_aggregate_pkey PRIMARY KEY (domain);


--
-- PostgreSQL database dump complete
--

