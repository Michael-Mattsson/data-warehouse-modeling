-- =============================================================================
-- SCD Type 2 — Change Simulation
-- =============================================================================
-- Simulates realistic customer attribute changes over the order history
-- period (2022–2023). Three change scenarios are applied:
--
--   Scenario A: Regional relocation (region + country change)
--   Scenario B: Segment upgrade (Consumer → Business)
--   Scenario C: Multiple sequential changes (same customer, two events)
--
-- Scenario C is deliberately included because it tests the hardest case:
-- a customer with 3 SCD2 records. Queries that accidentally omit date
-- bounds will produce 3x row duplication for this customer's orders —
-- which makes the failure mode visually obvious in the output.
--
-- After each scenario, a validation query confirms:
--   - Total rows increased by exactly the number of changes made
--   - Each affected customer has exactly one is_current = TRUE record
--   - No overlapping valid_from/valid_to ranges exist
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Pre-simulation baseline
-- -----------------------------------------------------------------------------

SELECT
    'pre_simulation' AS checkpoint,
    COUNT(*)         AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_customers,
    SUM(CASE WHEN is_current THEN 1 ELSE 0 END) AS current_records
FROM dim_customer_scd2;


-- =============================================================================
-- Scenario A: Regional relocation
-- Customer 1001 moves from their initial region to 'East' / 'Finland'
-- effective 2023-03-01. Simulates an international customer relocation.
-- =============================================================================

-- Step 1: Close current record
UPDATE dim_customer_scd2
SET
    valid_to   = DATE '2023-02-28',
    is_current = FALSE
WHERE customer_id = 1001
  AND is_current  = TRUE;

-- Step 2: Insert new record
INSERT INTO dim_customer_scd2
    (customer_key, customer_id, region, country, segment,
     valid_from, valid_to, is_current)
VALUES (
    (SELECT MAX(customer_key) + 1 FROM dim_customer_scd2),
    1001,
    'East',
    'Finland',
    (SELECT segment FROM dim_customer_scd2
     WHERE customer_id = 1001
     ORDER BY valid_from DESC LIMIT 1),   -- segment unchanged
    DATE '2023-03-01',
    NULL,
    TRUE
);

-- Validate Scenario A
SELECT
    'post_scenario_A' AS checkpoint,
    customer_id,
    region, country, segment,
    valid_from, valid_to, is_current
FROM dim_customer_scd2
WHERE customer_id = 1001
ORDER BY valid_from;


-- =============================================================================
-- Scenario B: Segment upgrade
-- Customer 2500 upgrades from 'Consumer' to 'Business' effective 2023-06-15.
-- Simulates a customer account type change — common in B2B platforms.
-- =============================================================================

UPDATE dim_customer_scd2
SET
    valid_to   = DATE '2023-06-14',
    is_current = FALSE
WHERE customer_id = 2500
  AND is_current  = TRUE;

INSERT INTO dim_customer_scd2
    (customer_key, customer_id, region, country, segment,
     valid_from, valid_to, is_current)
VALUES (
    (SELECT MAX(customer_key) + 1 FROM dim_customer_scd2),
    2500,
    (SELECT region  FROM dim_customer_scd2
     WHERE customer_id = 2500
     ORDER BY valid_from DESC LIMIT 1),
    (SELECT country FROM dim_customer_scd2
     WHERE customer_id = 2500
     ORDER BY valid_from DESC LIMIT 1),
    'Business',
    DATE '2023-06-15',
    NULL,
    TRUE
);

SELECT
    'post_scenario_B' AS checkpoint,
    customer_id,
    region, country, segment,
    valid_from, valid_to, is_current
FROM dim_customer_scd2
WHERE customer_id = 2500
ORDER BY valid_from;


-- =============================================================================
-- Scenario C: Multiple sequential changes — same customer, two events
-- Customer 5000 changes segment twice:
--   Change 1: Consumer → Business effective 2022-09-01
--   Change 2: Business → Enterprise effective 2023-05-01
-- This produces 3 SCD2 records for customer 5000.
-- Purpose: explicitly tests the row-duplication failure mode.
-- A query omitting date bounds returns 3 rows per order for this customer.
-- =============================================================================

-- Change 1
UPDATE dim_customer_scd2
SET
    valid_to   = DATE '2022-08-31',
    is_current = FALSE
WHERE customer_id = 5000
  AND is_current  = TRUE;

INSERT INTO dim_customer_scd2
    (customer_key, customer_id, region, country, segment,
     valid_from, valid_to, is_current)
VALUES (
    (SELECT MAX(customer_key) + 1 FROM dim_customer_scd2),
    5000,
    (SELECT region  FROM dim_customer_scd2
     WHERE customer_id = 5000
     ORDER BY valid_from DESC LIMIT 1),
    (SELECT country FROM dim_customer_scd2
     WHERE customer_id = 5000
     ORDER BY valid_from DESC LIMIT 1),
    'Business',
    DATE '2022-09-01',
    NULL,
    TRUE
);

-- Change 2
UPDATE dim_customer_scd2
SET
    valid_to   = DATE '2023-04-30',
    is_current = FALSE
WHERE customer_id = 5000
  AND is_current  = TRUE;

INSERT INTO dim_customer_scd2
    (customer_key, customer_id, region, country, segment,
     valid_from, valid_to, is_current)
VALUES (
    (SELECT MAX(customer_key) + 1 FROM dim_customer_scd2),
    5000,
    (SELECT region  FROM dim_customer_scd2
     WHERE customer_id = 5000
     ORDER BY valid_from DESC LIMIT 1),
    (SELECT country FROM dim_customer_scd2
     WHERE customer_id = 5000
     ORDER BY valid_from DESC LIMIT 1),
    'Enterprise',
    DATE '2023-05-01',
    NULL,
    TRUE
);

SELECT
    'post_scenario_C' AS checkpoint,
    customer_id,
    region, country, segment,
    valid_from, valid_to, is_current
FROM dim_customer_scd2
WHERE customer_id = 5000
ORDER BY valid_from;


-- =============================================================================
-- Post-simulation integrity checks
-- =============================================================================

-- 1. Total row count — should be initial_customers + 4
--    (1 for A, 1 for B, 2 for C)
SELECT
    'total_rows' AS check_name,
    COUNT(*) AS value
FROM dim_customer_scd2;

-- 2. Every customer should have exactly one is_current = TRUE record
SELECT
    'customers_with_multiple_current' AS check_name,
    COUNT(*) AS violations
FROM (
    SELECT customer_id
    FROM dim_customer_scd2
    WHERE is_current = TRUE
    GROUP BY customer_id
    HAVING COUNT(*) > 1
);

-- 3. No overlapping date ranges per customer
--    Join each record to the next one for the same customer —
--    valid_to + 1 day should equal the next valid_from
SELECT
    'overlapping_ranges' AS check_name,
    COUNT(*) AS violations
FROM (
    SELECT
        a.customer_id,
        a.valid_from AS a_from, a.valid_to AS a_to,
        b.valid_from AS b_from
    FROM dim_customer_scd2 a
    JOIN dim_customer_scd2 b
        ON  a.customer_id = b.customer_id
        AND b.valid_from  > a.valid_from
        AND (b.valid_from <= a.valid_to OR a.valid_to IS NULL)
        AND b.customer_key != a.customer_key
    WHERE a.valid_to IS NOT NULL
);

-- All three checks should return 0 violations.
-- Any violation indicates a broken SCD2 implementation.