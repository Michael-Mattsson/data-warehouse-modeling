-- =============================================================================
-- Idempotent Retry — Reference SQL
-- =============================================================================
-- Naive retry: blind INSERT, no conflict handling. Safe to run once.
-- Running it twice for the same (customer_id, night_number) produces
-- duplicates, since nothing prevents the second insert.
-- =============================================================================

-- Naive (dangerous on retry)
INSERT INTO retry_deltas
SELECT customer_id, 12 AS night_number, region, country, segment
FROM changed_rows;


-- -----------------------------------------------------------------------------
-- Idempotent upsert — DuckDB's ON CONFLICT clause, the equivalent of
-- standard SQL MERGE INTO:
--
--   MERGE INTO retry_deltas_idempotent AS target
--   USING changed_rows AS source
--   ON target.customer_id = source.customer_id
--  AND target.night_number = source.night_number
--   WHEN MATCHED THEN UPDATE SET region = source.region, ...
--   WHEN NOT MATCHED THEN INSERT (...) VALUES (...);
--
-- Requires a PRIMARY KEY or UNIQUE constraint on (customer_id, night_number)
-- for DuckDB to detect the conflict.
-- -----------------------------------------------------------------------------

INSERT INTO retry_deltas_idempotent
SELECT customer_id, 12 AS night_number, region, country, segment
FROM changed_rows
ON CONFLICT (customer_id, night_number) DO UPDATE SET
    region  = EXCLUDED.region,
    country = EXCLUDED.country,
    segment = EXCLUDED.segment;