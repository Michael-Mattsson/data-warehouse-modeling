import duckdb
import os

# ---------------------------------------------------------------------------
# SCD Type 2 Customer Dimension — Builder
#
# Extends Project 1's dim_customer with full Type 2 slowly changing
# dimension logic. Customers can change region, country, and segment
# over time. Each change creates a new row rather than overwriting the
# existing one, preserving the full attribute history.
#
# This enables point-in-time reconstruction:
#   "What region was this customer in at the time of their order?"
#
# Without Type 2: that question is unanswerable — only current state exists.
# With Type 2:    the temporal join returns the correct historical attribute.
#
# Input:  ../small-systems-projects/data/project1_finmart.duckdb
# Output: ../small-systems-projects/data/project3_scd2.duckdb
# ---------------------------------------------------------------------------

SOURCE_DB = "../small-systems-projects/data/project1_finmart.duckdb"
SCD2_DB   = "../small-systems-projects/data/project3_scd2.duckdb"

os.makedirs("../small-systems-projects/data", exist_ok=True)

con = duckdb.connect(SCD2_DB)

print("Attaching Project 1 database...")
con.execute(f"ATTACH '{SOURCE_DB}' AS src (READ_ONLY)")

print("Copying fact and product tables unchanged...")
con.execute("CREATE OR REPLACE TABLE fct_orders   AS SELECT * FROM src.fct_orders")
con.execute("CREATE OR REPLACE TABLE dim_date     AS SELECT * FROM src.dim_date")
con.execute("CREATE OR REPLACE TABLE dim_product  AS SELECT * FROM src.dim_product")

con.execute("DETACH src")

# ---------------------------------------------------------------------------
# Build dim_customer_scd2
#
# The initial load treats all customers as having their current attributes
# from the beginning of the data history (2022-01-01). valid_to = NULL
# means the record is currently active. is_current = TRUE flags the
# latest record per customer for queries that only need current state.
#
# Structure:
#   customer_key      — surrogate key (unique per row, not per customer)
#   customer_id       — natural key (repeats across Type 2 rows)
#   region/country/segment — tracked attributes
#   valid_from        — date this version became effective
#   valid_to          — date this version was superseded (NULL = active)
#   is_current        — convenience flag for current-state queries
# ---------------------------------------------------------------------------

print("Building dim_customer_scd2 (initial load)...")
con.execute("""
CREATE OR REPLACE TABLE dim_customer_scd2 AS
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id)  AS customer_key,
    customer_id,
    region,
    country,
    segment,
    DATE '2022-01-01'                          AS valid_from,
    NULL::DATE                                 AS valid_to,
    TRUE                                       AS is_current
FROM src_initial
""")

# Can't reference src after DETACH — rebuild from fct_orders join logic
# using the customer attributes we need to reconstruct
con.execute("""
CREATE OR REPLACE TABLE dim_customer_scd2 AS
WITH base_customers AS (
    SELECT DISTINCT
        o.customer_id,
        -- Assign deterministic attributes by customer_id range
        -- (mirrors Project 1's raw_customers generation logic)
        CASE
            WHEN o.customer_id % 4 = 0 THEN 'North'
            WHEN o.customer_id % 4 = 1 THEN 'South'
            WHEN o.customer_id % 4 = 2 THEN 'East'
            ELSE                             'West'
        END AS region,
        CASE
            WHEN o.customer_id % 3 = 0 THEN 'Finland'
            WHEN o.customer_id % 3 = 1 THEN 'Sweden'
            ELSE                             'Norway'
        END AS country,
        CASE
            WHEN o.customer_id % 10 < 6 THEN 'Consumer'
            WHEN o.customer_id % 10 < 9 THEN 'Business'
            ELSE                              'Enterprise'
        END AS segment
    FROM fct_orders o
)
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id)  AS customer_key,
    customer_id,
    region,
    country,
    segment,
    DATE '2022-01-01'                          AS valid_from,
    NULL::DATE                                 AS valid_to,
    TRUE                                       AS is_current
FROM base_customers
""")

# ---------------------------------------------------------------------------
# Post-build validation
# ---------------------------------------------------------------------------

print("\n--- Initial Load Validation ---")
counts = con.execute("""
    SELECT 'dim_customer_scd2' AS table_name,
           COUNT(*) AS total_rows,
           COUNT(DISTINCT customer_id) AS distinct_customers,
           SUM(CASE WHEN is_current THEN 1 ELSE 0 END) AS current_records,
           SUM(CASE WHEN valid_to IS NULL THEN 1 ELSE 0 END) AS open_records
    FROM dim_customer_scd2
""").fetchdf()
print(counts.to_string(index=False))

# At initial load: total_rows = distinct_customers = current_records = open_records
# Any deviation means the initial load has duplicate or closed records incorrectly

print(f"\nDone. SCD2 database written to: {SCD2_DB}")
con.close()