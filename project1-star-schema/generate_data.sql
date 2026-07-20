-- =============================================================================
-- FinMart Sales Data — Synthetic Data Generation
-- =============================================================================
-- Creates the raw source tables used throughout Project 1.
--
-- Output tables
--   • raw_orders
--   • raw_customers
--   • raw_products
--
-- The data intentionally resembles an e-commerce transactional system
-- rather than a warehouse model.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- raw_orders
--
-- Grain: One row per order line.
--
-- Generates approximately five million synthetic orders across two years.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE raw_orders AS
SELECT
    ROW_NUMBER() OVER ()                                       AS order_id,
    (DATE '2022-01-01' + INTERVAL (RANDOM() * 730) DAY)::DATE  AS order_date,
    FLOOR(RANDOM() * 10000 + 1)::INT                           AS customer_id,
    FLOOR(RANDOM() * 500 + 1)::INT                             AS product_id,
    FLOOR(RANDOM() * 10 + 1)::INT                              AS quantity,
    ROUND((RANDOM() * 200 + 5)::NUMERIC, 2)                    AS unit_price,
    CASE
        WHEN RANDOM() < 0.05 THEN TRUE
        ELSE FALSE
    END                                                        AS is_refunded
FROM RANGE(5000000);


-- -----------------------------------------------------------------------------
-- raw_customers
--
-- Grain:
-- One row per customer appearing in raw_orders.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE raw_customers AS
SELECT
    customer_id,

    CASE
        WHEN RANDOM() < 0.22 THEN 'North'
        WHEN RANDOM() < 0.50 THEN 'South'
        WHEN RANDOM() < 0.82 THEN 'East'
        ELSE                      'West'
    END AS region,

    CASE
        WHEN RANDOM() < 0.23 THEN 'Finland'
        WHEN RANDOM() < 0.71 THEN 'Sweden'
        ELSE                      'Norway'
    END AS country,

    CASE
        WHEN RANDOM() < 0.60 THEN 'Consumer'
        WHEN RANDOM() < 0.90 THEN 'Business'
        ELSE                      'Enterprise'
    END AS segment

FROM (
    SELECT DISTINCT customer_id
    FROM raw_orders
);


-- -----------------------------------------------------------------------------
-- raw_products
--
-- Grain:
-- One row per product appearing in raw_orders.
--
-- Categories and costs remain static for this project.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE raw_products AS
SELECT
    product_id,

    CONCAT('Product_', product_id)                             AS product_name,

    CASE
        WHEN product_id <= 110 THEN 'Electronics'
        WHEN product_id <= 265 THEN 'Home'
        WHEN product_id <= 325 THEN 'Sports'
        ELSE                        'Clothing'
    END AS category,

    CASE
        WHEN product_id % 20 < 8 THEN 'Premium'
        WHEN product_id % 20 < 15 THEN 'Standard'
        WHEN product_id % 20 < 18 THEN 'Budget'
        ELSE                         'Specialty'
    END AS subcategory,

    ROUND((RANDOM() * 100 + 2)::NUMERIC, 2)                    AS cost_price

FROM (
    SELECT DISTINCT product_id
    FROM raw_orders
);