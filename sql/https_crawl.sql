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
-- Name: https_crawl; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE https_crawl (
    domain text NOT NULL,
    http_request_uri text,
    http_response integer,
    http_requests integer,
    http_size integer,
    https_request_uri text,
    https_response integer,
    https_requests integer,
    https_size integer,
    "timestamp" timestamp with time zone DEFAULT now(),
    screenshot_diff real,
    id bigint,
    autoupgrade boolean,
    mixed boolean
);


--
-- Name: https_crawl_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE https_crawl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: https_crawl_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE https_crawl_id_seq OWNED BY https_crawl.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY https_crawl ALTER COLUMN id SET DEFAULT nextval('https_crawl_id_seq'::regclass);


--
-- Name: https_crawl_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY https_crawl
    ADD CONSTRAINT https_crawl_id_key UNIQUE (id);


--
-- Name: https_crawl_domain_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX https_crawl_domain_idx ON https_crawl USING btree (domain);


--
-- PostgreSQL database dump complete
--

