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

--
-- Name: upgradeable_domains(real, real, real, real, real); Type: FUNCTION; Schema: public; Owner: - 
--

CREATE OR REPLACE FUNCTION upgradeable_domains(
    unknown_max real,
    combined_min real,
    screenshot_diff_max real,
    mixed_ok boolean DEFAULT TRUE,
    autoupgrade_min real DEFAULT 0,
    ssl_cert_buffer timestamp with time zone DEFAULT now(),
    exclude_issuers text[] default '{}',
    max_err_rate real DEFAULT 1)
    RETURNS TABLE(domain character varying) AS
$$
    select domain from https_upgrade_metrics m
        where
        (unknown_pct <= unknown_max) and
        (combined_min <= combined_pct) and
        (max_screenshot_diff <= screenshot_diff_max) and
        (upgradeable_domains.mixed_ok = m.mixed_ok) and
        (autoupgrade_min <= autoupgrade_pct) and
        (https_err_rate <= max_err_rate)
    except
    (
        select domain from domain_exceptions
        union
        select domain from ssl_cert_info
            where
            err is not null or
            host_valid = false or
            notafter < ssl_cert_buffer or
            notbefore is null or
            notafter is null or
            issuer is null or
            issuer ~* ANY(exclude_issuers)
    )
$$ LANGUAGE sql RETURNS NULL ON NULL INPUT;


--
-- PostgreSQL database dump complete
--

