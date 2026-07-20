import duckdb
from pathlib import Path

# ---------------------------------------------------------------------------
# FinMart Star Schema — Schema Build
#
# Executes build_schema.sql to construct the dimensional warehouse
# from the generated raw source tables.
#
# Input tables:
#     raw_orders
#     raw_customers
#     raw_products
#
# Output tables:
#     dim_date
#     dim_customer
#     dim_product
#     fct_orders
# ---------------------------------------------------------------------------

DB_PATH = "data/project1_finmart.duckdb"
SQL_PATH = Path(__file__).with_name("build_schema.sql")

con = duckdb.connect(DB_PATH)

# ---------------------------------------------------------------------------
# Execute schema build
# ---------------------------------------------------------------------------

sql = SQL_PATH.read_text(encoding="utf-8")
con.execute(sql)

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

checks = {
    "raw_orders":
        "SELECT COUNT(*) FROM raw_orders",

    "dim_date":
        "SELECT COUNT(*) FROM dim_date",

    "dim_customer":
        "SELECT COUNT(*) FROM dim_customer",

    "dim_product":
        "SELECT COUNT(*) FROM dim_product",

    "fct_orders":
        "SELECT COUNT(*) FROM fct_orders",

    "unmatched date keys":
        """
        SELECT COUNT(*)
        FROM fct_orders
        WHERE date_key NOT IN (
            SELECT date_key
            FROM dim_date
        )
        """,

    "unmatched customer keys":
        """
        SELECT COUNT(*)
        FROM fct_orders
        WHERE customer_key NOT IN (
            SELECT customer_key
            FROM dim_customer
        )
        """,

    "unmatched product keys":
        """
        SELECT COUNT(*)
        FROM fct_orders
        WHERE product_key NOT IN (
            SELECT product_key
            FROM dim_product
        )
        """
}

print("Schema validation")
print("-----------------")

for label, query in checks.items():
    result = con.execute(query).fetchone()[0]
    print(f"{label:<30} {result:,}")

print("\nStar schema built successfully.")

con.close()