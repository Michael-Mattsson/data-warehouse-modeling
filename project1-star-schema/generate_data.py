import duckdb
import os
from pathlib import Path

# ---------------------------------------------------------------------------
# FinMart Sales Data — Synthetic Data Generation
#
# Executes the SQL in generate_data.sql to create the raw source tables
# simulating an e-commerce order system.
#
# Output:
#     data/project1_finmart.duckdb
#
# Tables:
#     raw_orders
#     raw_customers
#     raw_products
# ---------------------------------------------------------------------------

DB_PATH = "data/project1_finmart.duckdb"
SQL_PATH = Path(__file__).with_name("generate_data.sql")

os.makedirs("data", exist_ok=True)

con = duckdb.connect(DB_PATH)

# ---------------------------------------------------------------------------
# Data generation SQL
# ---------------------------------------------------------------------------

with open(SQL_PATH, "r", encoding="utf-8") as f:
    con.execute(f.read())

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

checks = {
    "raw_orders row count":
        "SELECT COUNT(*) FROM raw_orders",

    "raw_customers row count":
        "SELECT COUNT(*) FROM raw_customers",

    "raw_products row count":
        "SELECT COUNT(*) FROM raw_products",

    "orders with null date":
        "SELECT COUNT(*) FROM raw_orders WHERE order_date IS NULL",

    "orders with null price":
        "SELECT COUNT(*) FROM raw_orders WHERE unit_price IS NULL",

    "customers with null region":
        "SELECT COUNT(*) FROM raw_customers WHERE region IS NULL",
}

print("Validation\n----------")

for label, query in checks.items():
    result = con.execute(query).fetchone()[0]
    print(f"{label:<35} {result:,}")

print(f"\nDatabase written to: {DB_PATH}")

con.close()