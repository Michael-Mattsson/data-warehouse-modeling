# Section 2 — Warehouse Architecture & Modeling Systems

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

## Stack
DuckDB · SQL · Python (data generation) · Markdown (documentation)

## Key Concepts Demonstrated
Surrogate keys · Conformed dimensions · Temporal joins · 
Join cardinality · Grain decisions · Postmortem documentation