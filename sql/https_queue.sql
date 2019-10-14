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
-- Name: https_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE https_queue (
    rank integer NOT NULL,
    domain character varying(500) NOT NULL,
    processing_host character varying(50),
    worker_pid integer,
    reserved timestamp with time zone,
    started timestamp with time zone,
    finished timestamp with time zone,
    CONSTRAINT domain_is_lowercase CHECK (((domain)::text = lower((domain)::text)))
);


--
-- Name: https_queue_rank_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE https_queue_rank_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
    CYCLE;


--
-- Name: https_queue_rank_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE https_queue_rank_seq OWNED BY https_queue.rank;


--
-- Name: rank; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY https_queue ALTER COLUMN rank SET DEFAULT nextval('https_queue_rank_seq'::regclass);


--
-- Name: https_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY https_queue
    ADD CONSTRAINT https_queue_pkey PRIMARY KEY (rank);


--
-- Name: https_queue_domain_finished_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX https_queue_domain_finished_idx ON https_queue USING btree (domain, finished);


--
-- Name: https_queue_processing_host_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX https_queue_processing_host_idx ON https_queue USING btree (processing_host);


--
-- PostgreSQL database dump complete
--

