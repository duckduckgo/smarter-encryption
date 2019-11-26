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
-- Name: https_response_headers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE https_response_headers (
    https_crawl_id bigint NOT NULL,
    response_headers jsonb NOT NULL
);


--
-- Name: https_response_headers_https_crawl_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX https_response_headers_https_crawl_id_idx ON https_response_headers USING btree (https_crawl_id);


--
-- Name: https_response_headers_response_headers_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX https_response_headers_response_headers_idx ON https_response_headers USING gin (response_headers);


--
-- Name: https_response_headers_https_crawl_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY https_response_headers
    ADD CONSTRAINT https_response_headers_https_crawl_id_fkey FOREIGN KEY (https_crawl_id) REFERENCES https_crawl(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

