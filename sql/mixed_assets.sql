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
-- Name: mixed_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE mixed_assets (
    asset text NOT NULL,
    https_crawl_id bigint NOT NULL
);


--
-- Name: mixed_assets_unique_substrmd5_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mixed_assets_unique_substrmd5_idx ON mixed_assets USING btree (https_crawl_id, "left"(md5(asset), 8));


--
-- Name: mixed_assets_https_crawl_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY mixed_assets
    ADD CONSTRAINT mixed_assets_https_crawl_id_fkey FOREIGN KEY (https_crawl_id) REFERENCES https_crawl(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

