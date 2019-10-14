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
-- Name: full_urls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE full_urls (
    host text NOT NULL,
    url text NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: full_urls_host_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX full_urls_host_idx ON full_urls USING btree (host);


--
-- Name: full_urls_unique_substrmd5_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX full_urls_unique_substrmd5_idx ON full_urls USING btree (host, "left"(md5(url), 8));


--
-- PostgreSQL database dump complete
--

