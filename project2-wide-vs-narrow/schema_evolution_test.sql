-- =============================================================================
-- Schema Evolution Test
-- =============================================================================
-- Goal:
-- Compare maintenance cost when business requirements change.
--
-- Query benchmarks measure runtime performance.
-- These scenarios measure schema adaptability and operational impact.
--
-- For each change:
--   Narrow = update dimension tables only.
--   Wide   = update source dimension AND propagate to wide_orders.
-- =============================================================================

-- Change 1: Add new attribute to product dimension
-- NARROW SCHEMA
ALTER TABLE dim_product
ADD COLUMN brand VARCHAR;

UPDATE dim_product
SET brand =
    CASE
        WHEN category = 'Electronics' THEN 'TechCorp'
        WHEN category = 'Home'        THEN 'HomeStyle'
        WHEN category = 'Sports'      THEN 'SportMax'
        ELSE                              'FashionCo'
    END;

-- dim_product = 500 rows

-- WIDE SCHEMA
ALTER TABLE dim_product
ADD COLUMN brand VARCHAR;

UPDATE dim_product
SET brand =
    CASE
        WHEN category = 'Electronics' THEN 'TechCorp'
        WHEN category = 'Home'        THEN 'HomeStyle'
        WHEN category = 'Sports'      THEN 'SportMax'
        ELSE                              'FashionCo'
    END;

-- Propagate into denormalized table
ALTER TABLE wide_orders
ADD COLUMN brand VARCHAR;

UPDATE wide_orders w
SET brand = (
    SELECT p.brand
    FROM dim_product p
    WHERE p.product_id = w.product_id
);

-- dim_product = 500 rows
-- wide_orders = 5,000,000 rows


-- Change 2: Add new customer classification
-- NARROW SCHEMA
ALTER TABLE dim_customer
ADD COLUMN customer_lifetime_segment VARCHAR;

UPDATE dim_customer
SET customer_lifetime_segment =
    CASE
        WHEN segment = 'Enterprise' THEN 'High Value'
        WHEN segment = 'Business'   THEN 'Medium Value'
        ELSE                             'Standard'
    END;

-- dim_customer = 10,000 rows

-- WIDE SCHEMA
ALTER TABLE dim_customer
ADD COLUMN customer_lifetime_segment VARCHAR;

UPDATE dim_customer
SET customer_lifetime_segment =
    CASE
        WHEN segment = 'Enterprise' THEN 'High Value'
        WHEN segment = 'Business'   THEN 'Medium Value'
        ELSE                             'Standard'
    END;

-- Propagate into denormalized table
ALTER TABLE wide_orders
ADD COLUMN customer_lifetime_segment VARCHAR;

UPDATE wide_orders w
SET customer_lifetime_segment = (
    SELECT c.customer_lifetime_segment
    FROM dim_customer c
    WHERE c.customer_id = w.customer_id
);

-- dim_customer = 10,000 rows
-- wide_orders = 5,000,000 rows


-- Change 3: Replace Segment with Customer Tier (e.g., Bronze, Silver, Gold)
-- NARROW SCHEMA
ALTER TABLE dim_customer
ADD COLUMN customer_tier VARCHAR;

UPDATE dim_customer
SET customer_tier =
    CASE
        WHEN segment = 'Consumer'   THEN 'Bronze'
        WHEN segment = 'Business'   THEN 'Silver'
        WHEN segment = 'Enterprise' THEN 'Gold'
    END;

ALTER TABLE dim_customer
DROP COLUMN segment;

-- dim_customer = 10,000 rows

-- WIDE SCHEMA
ALTER TABLE wide_orders
ADD COLUMN customer_tier VARCHAR;

UPDATE wide_orders
SET customer_tier =
    CASE
        WHEN segment = 'Consumer'   THEN 'Bronze'
        WHEN segment = 'Business'   THEN 'Silver'
        WHEN segment = 'Enterprise' THEN 'Gold'
    END;

ALTER TABLE wide_orders
DROP COLUMN segment;

-- wide_orders = 5,000,000 rows


-- =============================================================================
-- Summary
-- =============================================================================
-- Propagation multiplier = wide rows touched / narrow rows touched.
-- Represents how many times more expensive the same logical change is
-- in the wide schema compared to the narrow schema.
-- =============================================================================

SELECT
    change_number,
    description,
    narrow_rows_touched,
    wide_rows_touched,
    ROUND(
        wide_rows_touched::NUMERIC / NULLIF(narrow_rows_touched, 0), 0
    ) AS propagation_multiplier
FROM (VALUES
    (1, 'Add product brand',                    500,   5000000),
    (2, 'Add customer_lifetime_segment',       10000,  5000000),
    (3, 'Replace segment with customer_tier',  10000,  5000000)
) AS t(change_number, description, narrow_rows_touched, wide_rows_touched)
ORDER BY change_number;

-- A change costing 500 rows in the narrow schema costs 5,000,000 rows
-- in the wide schema — the same logical operation at 500–10,000x the
-- operational impact depending on which dimension is affected.
