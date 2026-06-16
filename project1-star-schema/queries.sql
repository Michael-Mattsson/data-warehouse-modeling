
- =============================================================================
-- FinMart Star Schema — Analytical Queries
-- =============================================================================
-- All queries join through surrogate keys to dimension tables.
-- Revenue columns reference precomputed fct_orders fields (net_revenue,
-- gross_revenue) rather than recalculating unit_price * quantity inline.
-- This ensures consistent metric definitions across all consumers.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Schema validation
-- Run after build_schema.sql to confirm row counts and FK integrity.
-- fct_orders row count should exactly match raw_orders row count.
-- Any unmatched FK rows indicate a join failure during schema build.
-- -----------------------------------------------------------------------------

SELECT 'raw_orders'  AS table_name, COUNT(*) AS rows FROM raw_orders
UNION ALL SELECT 'dim_date',     COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_product',  COUNT(*) FROM dim_product
UNION ALL SELECT 'fct_orders',   COUNT(*) FROM fct_orders;

SELECT 'unmatched_dates'      AS check_name, COUNT(*) AS unmatched_rows
FROM fct_orders
WHERE date_key NOT IN (SELECT date_key FROM dim_date)
UNION ALL
SELECT 'unmatched_customers', COUNT(*)
FROM fct_orders
WHERE customer_key NOT IN (SELECT customer_key FROM dim_customer)
UNION ALL
SELECT 'unmatched_products',  COUNT(*)
FROM fct_orders
WHERE product_key NOT IN (SELECT product_key FROM dim_product);


-- -----------------------------------------------------------------------------
-- Q1: Revenue by product category by quarter, excluding refunds
-- Validates: category dimension, date dimension, net_revenue metric
-- -----------------------------------------------------------------------------

SELECT
    p.category,
    d.year,
    d.quarter,
    COUNT(DISTINCT o.order_id)                          AS order_count,
    SUM(o.net_revenue)                                  AS net_revenue,
    ROUND(AVG(o.net_revenue), 2)                        AS avg_order_revenue
FROM fct_orders o
JOIN dim_product  p ON o.product_key = p.product_key
JOIN dim_date     d ON o.date_key    = d.date_key
GROUP BY p.category, d.year, d.quarter
ORDER BY p.category, d.year, d.quarter;


-- -----------------------------------------------------------------------------
-- Q2: Top 10 customers by net revenue in 2023
-- Validates: customer dimension FK, date filter through dim_date
-- Note: filtering on d.year rather than EXTRACT(YEAR FROM order_date)
-- ensures the filter uses the pre-calculated dimension attribute —
-- consistent with how all date filtering should work through dim_date.
-- -----------------------------------------------------------------------------

SELECT
    c.customer_id,
    c.region,
    c.segment,
    COUNT(DISTINCT o.order_id)                          AS order_count,
    SUM(o.net_revenue)                                  AS net_revenue
FROM fct_orders o
JOIN dim_customer c ON o.customer_key = c.customer_key
JOIN dim_date     d ON o.date_key     = d.date_key
WHERE d.year = 2023
GROUP BY c.customer_id, c.region, c.segment
ORDER BY net_revenue DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q3: Weekend vs weekday net revenue by region
-- Validates: is_weekend flag in dim_date, region from dim_customer
-- pct_of_region_revenue uses a window function to show share within
-- each region — avoids a second query or subquery for totals.
-- -----------------------------------------------------------------------------

SELECT
    c.region,
    CASE WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END            AS day_type,
    COUNT(DISTINCT o.order_id)                                          AS order_count,
    SUM(o.net_revenue)                                                  AS net_revenue,
    ROUND(
        SUM(o.net_revenue) /
        SUM(SUM(o.net_revenue)) OVER (PARTITION BY c.region) * 100, 1)  AS pct_of_region_revenue
FROM fct_orders o
JOIN dim_customer c ON o.customer_key = c.customer_key
JOIN dim_date     d ON o.date_key     = d.date_key
GROUP BY c.region, d.is_weekend
ORDER BY c.region, day_type;


-- -----------------------------------------------------------------------------
-- Q4: Month-over-month net revenue growth by category
-- Validates: LAG() across ordered time dimension, CTE structure
-- Two-CTE pattern: first aggregate to monthly grain, then apply LAG.
-- Collapsing into one CTE would require repeating the LAG expression
-- or using a subquery — the two-step pattern is more maintainable.
-- -----------------------------------------------------------------------------

WITH monthly_revenue AS (
    SELECT
        p.category,
        EXTRACT(YEAR FROM o.order_date)     AS year,
        EXTRACT(MONTH FROM o.order_date)    AS month,
        SUM(o.unit_price * o.quantity)      AS revenue
    FROM raw_orders o
    JOIN raw_products p ON o.product_id = p.product_id
    WHERE o.is_refunded = FALSE
    GROUP BY p.category, EXTRACT(YEAR FROM o.order_date), EXTRACT(MONTH FROM o.order_date)
)
SELECT
    category,
    year,
    month,
    revenue,
    LAG(revenue) OVER (PARTITION BY category ORDER BY year, month) AS previous_month_revenue,
    CASE
        WHEN LAG(revenue) OVER (PARTITION BY category ORDER BY year, month) IS NULL THEN NULL
        ELSE (revenue - LAG(revenue) OVER (PARTITION BY category ORDER BY year, month)) / LAG(revenue) OVER (PARTITION BY category ORDER BY year, month) * 100
    END AS revenue_growth_pct
FROM monthly_revenue


-- -----------------------------------------------------------------------------
-- Q5: Gross vs net revenue by category — refund impact analysis
-- Validates: both gross_revenue and net_revenue precomputed columns,
-- confirms refund rate is consistent with the 5% generation probability.
-- Expected: refund_rate_pct should cluster around 5% across categories.
-- Any significant deviation from 5% would indicate a data generation issue.
-- -----------------------------------------------------------------------------

SELECT
    p.category,
    SUM(o.gross_revenue)                                  AS gross_revenue,
    SUM(o.net_revenue)                                    AS net_revenue,
    SUM(o.gross_revenue) - SUM(o.net_revenue)             AS refund_value,
    ROUND(
        (SUM(o.gross_revenue) - SUM(o.net_revenue))
        / SUM(o.gross_revenue) * 100
    , 2)                                                  AS refund_rate_pct
FROM fct_orders o
JOIN dim_product p ON o.product_key = p.product_key
GROUP BY p.category
ORDER BY refund_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- Q6: Revenue and margin by product subcategory
-- Validates: cost_price join from dim_product, margin calculation
-- NULLIF guard on net_revenue prevents division by zero on empty segments.
-- margin_pct = (revenue - cost) / revenue — contribution margin, not
-- gross margin. Gross margin would require unit cost, not total cost.
-- -----------------------------------------------------------------------------

SELECT
    p.category,
    p.subcategory,
    SUM(o.net_revenue)                                      AS net_revenue,
    SUM(o.quantity * p.cost_price)                          AS total_cost,
    ROUND(
        (SUM(o.net_revenue) - SUM(o.quantity * p.cost_price))
        / NULLIF(SUM(o.net_revenue), 0) * 100
    , 1)                                                    AS margin_pct
FROM fct_orders o
JOIN dim_product p ON o.product_key = p.product_key
GROUP BY p.category, p.subcategory
ORDER BY p.category, margin_pct DESC;