import duckdb
import pandas as pd

# ---------------------------------------------------------------------------
# SCD Type 2 — Point-in-Time Query Runner
#
# Executes all analytical queries from point_in_time_queries.sql and
# prints results with labeled sections. Most importantly, runs the
# broken join alongside the correct join and shows the inflation
# quantification query so the failure mode is immediately visible.
# ---------------------------------------------------------------------------

DB_PATH = "../small-systems-projects/data/project3_scd2.duckdb"

con = duckdb.connect(DB_PATH)
pd.set_option("display.float_format", "{:,.2f}".format)
pd.set_option("display.max_columns", 20)
pd.set_option("display.width", 120)


def run(label, query, limit=None):
    print(f"\n{'='*65}")
    print(f"  {label}")
    print(f"{'='*65}")
    if limit is not None:
        query = f"SELECT * FROM ({query}) sub LIMIT {limit}"
    result = con.execute(query).fetchdf()
    print(result.to_string(index=False))


# ---------------------------------------------------------------------------
# Section 1: Dimension health after simulate_changes.sql
# ---------------------------------------------------------------------------

run("SCD2 dimension overview — version counts per customer", """
    SELECT
        COUNT(*)                                                 AS total_rows,
        COUNT(DISTINCT customer_id)                              AS distinct_customers,
        ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT customer_id), 4)
                                                                 AS avg_versions_per_customer,
        SUM(CASE WHEN is_current THEN 1 ELSE 0 END)              AS current_records,
        SUM(CASE WHEN valid_to IS NULL THEN 1 ELSE 0 END)        AS open_records
    FROM dim_customer_scd2
""")

run("Changed customers — version counts", """
    SELECT
        customer_id,
        COUNT(*) AS version_count
    FROM dim_customer_scd2
    GROUP BY customer_id
    HAVING COUNT(*) > 1
    ORDER BY version_count DESC, customer_id;
""")

run("Changed customers — full version history", """
    SELECT
        customer_id, region, country, segment,
        valid_from, valid_to, is_current
    FROM dim_customer_scd2
    WHERE customer_id IN (1001, 2500, 5000)
    ORDER BY customer_id, valid_from
""")


# ---------------------------------------------------------------------------
# Section 2: Correct vs broken join comparison
# ---------------------------------------------------------------------------

run("CORRECT — revenue by region using region at time of order", """
    SELECT
        c.region AS region_at_order,
        d.year,
        SUM(o.net_revenue)          AS net_revenue,
        COUNT(DISTINCT o.order_id)  AS order_count
    FROM fct_orders o
    JOIN dim_customer_scd2 c
        ON  o.customer_id  = c.customer_id
        AND o.order_date  >= c.valid_from
        AND (o.order_date  < c.valid_to OR c.valid_to IS NULL)
    JOIN dim_date d ON o.date_key = d.date_key
    GROUP BY c.region, d.year
    ORDER BY d.year, net_revenue DESC
""")

run("BROKEN — same query, date bounds omitted (inflated revenue)", """
    SELECT
        c.region,
        COUNT(*)           AS row_count,
        SUM(o.net_revenue) AS inflated_revenue
    FROM fct_orders o
    JOIN dim_customer_scd2 c
        ON o.customer_id = c.customer_id
    GROUP BY c.region
    ORDER BY inflated_revenue DESC
""")


# ---------------------------------------------------------------------------
# Section 3: Revenue inflation quantification
# ---------------------------------------------------------------------------

run("Revenue inflation by customer — correct vs broken join", """
    WITH correct AS (
        SELECT
            o.customer_id,
            SUM(o.net_revenue) AS correct_revenue,
            COUNT(*)           AS correct_row_count
        FROM fct_orders o
        JOIN dim_customer_scd2 c
            ON  o.customer_id  = c.customer_id
            AND o.order_date  >= c.valid_from
            AND (o.order_date  < c.valid_to OR c.valid_to IS NULL)
        WHERE o.customer_id IN (1001, 2500, 5000)
        GROUP BY o.customer_id
    ),
    broken AS (
        SELECT
            o.customer_id,
            SUM(o.net_revenue) AS inflated_revenue,
            COUNT(*)           AS inflated_row_count
        FROM fct_orders o
        JOIN dim_customer_scd2 c
            ON o.customer_id = c.customer_id
        WHERE o.customer_id IN (1001, 2500, 5000)
        GROUP BY o.customer_id
    ),
    versions AS (
        SELECT customer_id, COUNT(*) AS version_count
        FROM dim_customer_scd2
        WHERE customer_id IN (1001, 2500, 5000)
        GROUP BY customer_id
    )
    SELECT
        c.customer_id,
        v.version_count,
        c.correct_row_count,
        b.inflated_row_count,
        ROUND(c.correct_revenue, 2)  AS correct_revenue,
        ROUND(b.inflated_revenue, 2) AS inflated_revenue,
        ROUND(b.inflated_revenue / NULLIF(c.correct_revenue, 0), 2) AS inflation_factor
    FROM correct c
    JOIN broken b   ON c.customer_id = b.customer_id
    JOIN versions v ON c.customer_id = v.customer_id
    ORDER BY c.customer_id
""")


# ---------------------------------------------------------------------------
# Section 4: Point-in-time business questions
# ---------------------------------------------------------------------------

run("Customer 5000 — segment at time of each order", """
    SELECT
        o.order_id,
        o.order_date,
        ROUND(o.net_revenue, 2) AS net_revenue,
        c.segment               AS segment_at_order,
        c.valid_from,
        c.valid_to
    FROM fct_orders o
    JOIN dim_customer_scd2 c
        ON  o.customer_id  = c.customer_id
        AND o.order_date  >= c.valid_from
        AND (o.order_date  < c.valid_to OR c.valid_to IS NULL)
    WHERE o.customer_id = 5000
    ORDER BY o.order_date
""", limit=15)

run("Customer journey — revenue per segment version, changed customers only", """
    SELECT
        c.customer_id,
        c.segment,
        c.valid_from,
        c.valid_to,
        c.is_current,
        COALESCE(ROUND(SUM(o.net_revenue), 2), 0) AS revenue_during_period,
        COUNT(o.order_id)                          AS orders_during_period
    FROM dim_customer_scd2 c
    LEFT JOIN fct_orders o
        ON  o.customer_id  = c.customer_id
        AND o.order_date  >= c.valid_from
        AND (o.order_date  < c.valid_to OR c.valid_to IS NULL)
    WHERE c.customer_id IN (1001, 2500, 5000)
    GROUP BY
        c.customer_id, c.segment, c.valid_from,
        c.valid_to, c.is_current
    ORDER BY c.customer_id, c.valid_from
""")


# ---------------------------------------------------------------------------
# Section 5: Integrity checks
# ---------------------------------------------------------------------------

run("Integrity — customers with multiple is_current = TRUE (expect 0)", """
    SELECT COUNT(*) AS violations
    FROM (
        SELECT customer_id
        FROM dim_customer_scd2
        WHERE is_current = TRUE
        GROUP BY customer_id
        HAVING COUNT(*) > 1
    )
""")

run("Integrity — overlapping date ranges (expect 0)", """
    SELECT COUNT(*) AS violations
    FROM (
        SELECT a.customer_id
        FROM dim_customer_scd2 a
        JOIN dim_customer_scd2 b
            ON  a.customer_id  = b.customer_id
            AND b.valid_from   > a.valid_from
            AND b.valid_from  <= a.valid_to
            AND a.valid_to    IS NOT NULL
            AND b.customer_key != a.customer_key
    )
""")

print("\nAll queries complete.")
con.close()