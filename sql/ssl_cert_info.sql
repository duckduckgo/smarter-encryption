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
-- Name: ssl_cert_info; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE ssl_cert_info (
    domain text NOT NULL,
    issuer text,
    notbefore timestamp with time zone,
    notafter timestamp with time zone,
    host_valid boolean,
    err text,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ssl_cert_info_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ssl_cert_info
    ADD CONSTRAINT ssl_cert_info_pkey PRIMARY KEY (domain);


--
-- Name: ssl_cert_info_host_valid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ssl_cert_info_host_valid_idx ON ssl_cert_info USING btree (host_valid);


--
-- Name: ssl_cert_info_issuer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ssl_cert_info_issuer_idx ON ssl_cert_info USING btree (issuer);


--
-- Name: ssl_cert_info_notafter_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ssl_cert_info_notafter_idx ON ssl_cert_info USING btree (notafter);


--
-- PostgreSQL database dump complete
--

