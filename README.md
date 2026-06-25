# Warehouse Architecture & Modeling Systems

Four production-focused modeling projects covering star schema design, 
denormalization tradeoffs, SCD Type 2 history, and metric inflation debugging.

## Projects
1. **Star Schema** — NorthMart e-commerce, 2M orders, 
   3 conformed dimensions, documented grain decisions
2. **Wide vs Narrow Benchmark** — query performance and 
   schema evolution tradeoff analysis with recommendation memo
3. **SCD Type 2** — point-in-time customer dimension with 
   temporal join patterns and inflation trap documentation
4. **Metric Inflation** — root cause analysis of 35% revenue 
   overcount from many-to-many join, three fix approaches compared

raw_orders
      │
      ▼
Project 1
fact_orders
dim_customer
dim_product
dim_date
      │
      ▼
Project 2
wide_orders


## Stack
DuckDB · SQL · Python (data generation) · Markdown (documentation)

## Key Concepts Demonstrated
Surrogate keys · Conformed dimensions · Temporal joins · 
Join cardinality · Grain decisions · Postmortem documentation


# Project 2 — Wide vs Narrow Table Benchmark

Benchmarks two data modeling approaches against identical analytical
workloads on a 5,000,000 row FinMart order dataset.

## What this tests
- Query performance: 4 query pairs (wide vs star schema) run 5 times
  each, first run discarded, remaining runs averaged with variance reported
- Storage cost: row count and duplicated dimension attribute bytes compared
- Schema evolution cost: 3 sequential changes measured by rows touched

## Files
| File | Purpose |
|------|---------|
| `build_tables.sql` | Attaches Project 1 database, copies star schema, builds wide table |
| `benchmark.py` | Runs all query pairs, reports timing with variance |
| `benchmark_queries.sql` | All 8 queries (4 pairs) for manual inspection |
| `schema_evolution_test.sql` | 3 schema changes executed on both designs |
| `tradeoff_analysis.md` | Recommendation memo with real benchmark numbers |

## How to run
```bash
# From project2-wide-vs-narrow/
mkdir data
python -c "import duckdb; duckdb.connect('data/project2_benchmark.duckdb')"
duckdb data/project2_benchmark.duckdb < build_tables.sql
python benchmark.py
```

## Key finding
[Fill in after running — one sentence summarizing the headline result]

## Stack
DuckDB · SQL · Python