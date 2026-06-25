-- =============================================================================
-- Wide vs Narrow Benchmark — Table Construction
-- =============================================================================
-- Source: Project 1's star schema database, regenerated at 5,000,000 rows.
-- This script attaches Project 1's database, copies the four star schema
-- tables into Project 2's own local database, then builds the wide table.
--
-- Copying rather than querying the attached database directly keeps
-- Project 2 self-contained and immune to Project 1's database being
-- modified, regenerated, or simply not open at the time these benchmarks
-- are rerun later.
-- =============================================================================

ATTACH '../small-systems-projects/data/project1_finmart.duckdb' AS src_project1;

-- -----------------------------------------------------------------------------
-- Copy the star schema as-is — this is the "narrow" side of the comparison.
-- No transformation, no rebuild. If Project 1's build_schema.sql is correct,
-- this is a straight snapshot.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE dim_date     AS SELECT * FROM src_project1.dim_date;
CREATE OR REPLACE TABLE dim_customer AS SELECT * FROM src_project1.dim_customer;
CREATE OR REPLACE TABLE dim_product  AS SELECT * FROM src_project1.dim_product;
CREATE OR REPLACE TABLE fct_orders   AS SELECT * FROM src_project1.fct_orders;

DETACH src_project1;

-- -----------------------------------------------------------------------------
-- Wide table: fully denormalized, all dimension attributes flattened in.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE wide_orders AS
SELECT
    o.order_id,
    d.date,
    d.year                 AS order_year,
    d.quarter              AS order_quarter,
    d.month                AS order_month,
    d.is_weekend,
    c.customer_id,
    c.region,
    c.country,
    c.segment,
    p.product_id,
    p.name                 AS product_name,
    p.category,
    p.subcategory,
    p.cost_price,
    o.quantity,
    o.unit_price,
    o.gross_revenue,
    o.is_refunded,
    o.net_revenue
FROM fct_orders o
JOIN dim_date     d ON o.date_key     = d.date_key
JOIN dim_customer c ON o.customer_key = c.customer_key
JOIN dim_product  p ON o.product_key  = p.product_key;

-- -----------------------------------------------------------------------------
-- Post-build validation
-- -----------------------------------------------------------------------------

SELECT 'fct_orders'   AS table_name, COUNT(*) AS row_count FROM fct_orders
UNION ALL SELECT 'wide_orders',   COUNT(*) FROM wide_orders
UNION ALL SELECT 'dim_date',      COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_customer',  COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_product',   COUNT(*) FROM dim_product;

-- Expect fct_orders and wide_orders to have identical row counts.

-- -----------------------------------------------------------------------------
-- Dimension Attribute Duplication Analysis
-- -----------------------------------------------------------------------------

SELECT
    'wide_orders' AS table_name,
    COUNT(*)      AS row_count,
    SUM(LENGTH(region) + LENGTH(country) + LENGTH(segment)
        + LENGTH(category) + LENGTH(subcategory))::BIGINT AS dim_attribute_bytes
FROM wide_orders;

SELECT
    'dim_customer' AS table_name,
    COUNT(*) AS row_count,
    SUM(
        LENGTH(region)
        + LENGTH(country)
        + LENGTH(segment)
    )::BIGINT AS dim_attribute_bytes
FROM dim_customer

UNION ALL

SELECT
    'dim_product' AS table_name,
    COUNT(*) AS row_count,
    SUM(
        LENGTH(category)
        + LENGTH(subcategory)
    )::BIGINT AS dim_attribute_bytes
FROM dim_product;