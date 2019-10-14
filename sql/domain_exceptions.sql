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
-- Name: domain_exceptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE domain_exceptions (
    domain text NOT NULL,
    comment text,
    updated timestamp with time zone NOT NULL default now()
);


--
-- Name: domain_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY domain_exceptions
    ADD CONSTRAINT domain_exceptions_pkey PRIMARY KEY (domain);


--
-- PostgreSQL database dump complete
--

