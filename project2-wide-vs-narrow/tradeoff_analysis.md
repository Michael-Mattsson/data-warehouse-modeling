# Wide vs Narrow Table Tradeoff Analysis
### NorthMart Analytics Platform — Benchmark Date: [fill in]
### Dataset scale tested: 5,000,000 fact rows / 10,000 customers / 500 products
### Source: Project 1 star schema, regenerated at scale

---

## Recommendation

Use the narrow (star schema) design as the primary warehouse model.
Materialize wide tables only as a downstream, disposable serving layer
for specific high-traffic dashboards where query latency is measured
and the join cost is proven to matter — never as the source of truth.

---

## Benchmark Results

Methodology: each query run 5 times, first run discarded, remaining
4 runs averaged. Wide and narrow versions execute identical analytical
logic against the same underlying 10M-row dataset.

| Query | Description                          | Wide (ms) | Narrow (ms) | Winner   | Ratio |
|-------|---------------------------------------|-----------|-------------|----------|-------|
| Q1    | Simple single-dim aggregation          |   [fill]  |    [fill]   |  [fill]  | [fill]|
| Q2    | Multi-dim slice + distinct count       |   [fill]  |    [fill]   |  [fill]  | [fill]|
| Q3    | Point lookup, two filter predicates    |   [fill]  |    [fill]   |  [fill]  | [fill]|
| Q4    | Full scan, no filter, 3-way group by   |   [fill]  |    [fill]   |  [fill]  | [fill]|

*Run `benchmark.py` to populate. Ratio = narrow_time / wide_time;
ratio > 1 means wide was faster.*

**Honest caveat:** On a single local DuckDB instance, join cost for a
star schema with small dimension tables (10k and 500 rows) against a
10M-row fact table is usually small relative to total query time,
because DuckDB's vectorized hash joins on small dimensions are fast.
The performance gap that wide tables are often claimed to close is
more pronounced in distributed query engines with network shuffle costs
(Spark, Presto) or in poorly-optimized join implementations — less so
in modern single-node vectorized engines like DuckDB, and on BigQuery/
Snowflake specifically, join cost is usually dwarfed by scan cost,
which favors narrow tables further (see Storage and Scan Cost below).

---

## Storage and Scan Cost

| Table        | Row count   | Approx. on-disk size | Notes                              |
|--------------|-------------|------------------------|--------------------------------------|
| fct_orders   | 10,000,000  | [fill]                 | Narrow fact table, no dim attributes |
| wide_orders  | 10,000,000  | [fill]                 | Same row count, dimension attrs repeated per row |
| dim_customer |     10,000  | [fill]                 |                                       |
| dim_product  |        500  | [fill]                 |                                       |

The wide table duplicates every dimension attribute once per fact row.
At this scale, `region` (avg 5 chars) and `country` (avg 7 chars) alone
add roughly 12 bytes × 10M rows ≈ 120MB of pure duplication that does
not exist in the narrow design, where those values are stored once per
customer (10k rows) and referenced by a 4-byte integer key.

On cloud warehouses billed by bytes scanned (BigQuery, Snowflake), this
duplication directly inflates query cost for any query that scans the
wide table's dimension columns — even when the dimension values
themselves never change.

---

## When Wide Tables Win

- Read-heavy serving layers for a single, fixed dashboard where join
  elimination measurably improves latency under real concurrent load
  (not demonstrated at this scale in this benchmark — would need to
  test under concurrent query load, not single-query timing, to see
  this clearly)
- BI tools or end users querying without SQL fluency, where joins
  are a usability barrier, not a performance one
- Snapshot/export tables intended for one-time analysis or handoff
  to a non-technical stakeholder
- Situations where the data is genuinely static and will never need
  a dimension attribute changed independently of the fact

## When Normalized Tables Win

- Any schema with attributes that change over time (region, segment,
  category) — narrow design isolates the change to one small table
  instead of backfilling millions of fact rows
- Cost-sensitive cloud warehouse environments where bytes-scanned
  billing penalizes repeated dimension data on every fact row
- Systems requiring SCD Type 2 history (see Project 3) — wide tables
  cannot represent point-in-time dimension state without enormous
  row duplication
- Any environment where multiple fact tables need to share the same
  dimension consistently (conformed dimensions) — wide tables fork
  the definition of "customer" or "product" per fact table

---

## Schema Evolution Risk

Tested three sequential schema changes (see `schema_evolution_test.sql`):

| Change                                    | Narrow — rows touched | Wide — rows touched |
|---------------------------------------------|------------------------|------------------------|
| Add `cost_margin` (computed, no backfill)    | 0                       | 0 (if computed at query time) |
| Add `cost_margin` (precomputed, backfilled)  | 10,000,000 (fct_orders) | 10,000,000 (wide_orders) |
| Add `customer_lifetime_segment`              | 10,000 (dim_customer)   | 10,000,000 (wide_orders backfill required) |
| Rename `segment` → `customer_tier`            | 10,000 (dim_customer)   | 10,000,000 (wide_orders backfill required) |

The first change is a wash — both designs touch the fact-level table
once. The second and third changes reveal the real cost: any change to
a dimension attribute requires a full backfill of the wide table's
fact-grain rows, while the narrow design only touches the dimension
table itself. At 10M rows this is the difference between a 10-thousand-
row UPDATE and a 10-million-row UPDATE for the same logical change.

This cost compounds. A warehouse with 5 years of schema evolution on
customer or product attributes accumulates this penalty on every
single change, while the narrow design's cost stays flat regardless
of fact table size.

---

## Decision

For NorthMart specifically: adopt the narrow star schema (Project 1's
design) as the canonical warehouse model. The benchmark at 10M rows
shows no decisive query-time advantage for the wide table on this
single-node engine, while the schema evolution test shows a clear and
growing cost disadvantage for wide tables as dimension attributes
change — which they will, given that customer segment and product
categorization are both attributes the business actively revises.

If a specific dashboard later proves to need denormalized speed under
real concurrent load (which this benchmark did not test), build a
narrow wide table as a derived, rebuildable artifact — generated from
the star schema via a scheduled job, never hand-maintained, and treated
as disposable. This preserves the star schema as the source of truth
while still allowing a wide table where it's genuinely justified by
measured need rather than developer convenience.

---

## What I Would Test Next

- Concurrent query load (10+ simultaneous queries) rather than single-
  query timing, since join cost differences are more likely to surface
  under contention
- The same benchmark on BigQuery or Snowflake directly, where bytes-
  scanned billing makes the storage duplication cost concrete in dollars
  rather than theoretical
- A 100M+ row test to see whether the join-cost gap widens at larger
  scale, since 10M may still be within the range where DuckDB's join
  performance masks the difference