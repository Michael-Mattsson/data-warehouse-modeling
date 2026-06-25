# Wide vs Narrow Table Tradeoff Analysis
### NorthMart Analytics Platform — Benchmark Date: [fill in]
### Dataset scale tested: 5,000,000 fact rows / 10,000 customers / 500 products
### Source: Project 1 star schema, regenerated at scale

---

## Recommendation

Use the narrow (star schema) design as the primary warehouse model.
Materialize wide tables only as a downstream, disposable serving layer for 
specific high-traffic dashboards where query latency is measured and the 
join cost is proven to matter — never as the canonical warehouse model.

---

## Benchmark Results

Methodology: each query run 5 times, first run discarded, remaining
4 runs averaged. Wide and narrow versions execute identical analytical
logic against the same underlying 5M-row dataset.

| Query | Description                            | Wide (ms) | Narrow (ms) | Winner   | Ratio  |
|-------|----------------------------------------|-----------|-------------|----------|--------|
| Q1    | Simple single-dim aggregation          |   10.27   |    14.86    |  wide    |  1.45  |
| Q2    | Multi-dim slice + distinct count       |   456.48  |    429.69   |  narrow  |  0.94  |
| Q3    | Point lookup, two filter predicates    |   16.20   |    14.37    |  narrow  |  0.89  |
| Q4    | Full scan, no filter, 3-way group by   |   36.41   |    41.12    |  wide    |  1.13  |

*Run `benchmark.py` to populate. Ratio = narrow_time / wide_time;
ratio > 1 means wide was faster and ratio < 1 means narrow was faster.*

**Honest caveat:** DuckDB is a modern analytical database optimized for joining large fact tables with small dimension tables. Because the dimension tables in this benchmark contain only 10,000 customers and 500 products, join overhead is relatively small compared with scanning 5 million fact rows. As a result, the performance difference between wide and narrow schemas is modest. Larger differences are more common in distributed query engines, where joins require moving data between machines.

---

## Storage and Scan Cost

| Table        | Row count   | Duplicated dimension text | Notes                                   |
|--------------|-------------|---------------------------|-----------------------------------------|
| fct_orders   | 5,000,000   | None                      | Narrow fact table, no dim attributes    |
| wide_orders  | 5,000,000   | 167,531,859 bytes         | Same row count, dimension attrs repeated|
| dim_customer |     10,000  | stored once               |                                         |
| dim_product  |        500  | stored once               |                                         |

The wide table duplicates every dimension attribute once per fact row.
At this scale, `region` (avg 5 chars) and `country` (avg 7 chars) alone
add roughly 12 bytes × 5M rows ≈ 60MB of pure duplication that does
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
- Machine learning feature tables where denormalized training datasets
  are exported once and reused many times.


## When Normalized Tables Win

- Any schema with attributes that change over time (region, segment,
  category) — narrow design isolates the change to one small table
  instead of backfilling millions of fact rows
- Cost-sensitive cloud warehouse environments where bytes-scanned
  billing penalizes repeated dimension data on every fact row
- Systems requiring SCD Type 2 history — wide tables cannot represent 
  point-in-time dimension state without enormous row duplication
- Any environment where multiple fact tables need to share the same
  dimension consistently (conformed dimensions) — wide tables fork
  the definition of "customer" or "product" per fact table

---

## Schema Evolution Risk

Tested three schema changes (see `schema_evolution_test.sql`).
Row counts reflect actual table sizes at 5M fact rows.

| Change                              | Narrow — rows touched  | Wide — rows touched     | Multiplier|
|-------------------------------------|------------------------|-------------------------|-----------|
| Add `product_brand`                 | 500 (dim_product)      | 5,000,000 (wide_orders) | 10,000x   |
| Add `customer_lifetime_segment`     | 10,000 (dim_customer)  | 5,000,000 (wide_orders) | 500x      |
| Replace `segment` → `customer_tier` | 10,000 (dim_customer)  | 5,000,000 (wide_orders) | 500x      |

The wide table's maintenance cost is driven by fact row count, not by
which dimension changed or how large that dimension is. A change to a
500-row product dimension costs the same 5,000,000-row propagation as a
change to a 10,000-row customer dimension. This cost compounds with
every schema change over the life of the warehouse.


## Cost of Change

| Change                          | Wide        | Star   |Notes                                                     |
|---------------------------------|-------------|--------|----------------------------------------------------------|
| Add product attribute           | High        | Low    | Wide: 5M-row backfill. Star: 500-row dim update.         |
| Correct customer region         | High        | Low    | Wide: 5M-row backfill. Star: 10k-row dim update.         |
| Add SCD Type 2                  | Very High   | Medium | Wide cannot represent point-in-time state without full rebuild. Star extends naturally in Project 3. |
| New dashboard metric            | Low         | Low    | Both require a query or model change only.               |

Query benchmarks measure runtime performance. Schema evolution scenarios
measure maintenance cost. A design that is faster to query but requires
10,000x more rows touched per schema change may not be the right
long-term choice.


---

## Decision

For NorthMart specifically: adopt the narrow star schema (Project 1's
design) as the canonical warehouse model. The benchmark at 5M rows
shows no decisive query-time advantage for the wide table on this
single-node engine, while the schema evolution test shows a clear and
growing cost disadvantage for wide tables as dimension attributes
change — which they will, given that customer segment and product
categorization are both attributes the business actively revises.

If a specific dashboard later proves to need denormalized speed under
real concurrent load, build a narrow wide table as a derived, rebuildable 
artifact — generated from the star schema via a scheduled job, never 
hand-maintained, and treated as disposable. This preserves the star 
schema as the canonical warehouse model while still allowing a wide table where 
it's genuinely justified by measured need rather than developer convenience.

---

## Limitations

• Single-node DuckDB only
• 5 million rows
• Four representative workloads
• No concurrent users
• No network latency
• No cloud storage costs

--

## What I Would Test Next

- Concurrent query load (10+ simultaneous queries) rather than single-
  query timing, since join cost differences are more likely to surface
  under contention
- The same benchmark on BigQuery or Snowflake directly, where bytes-
  scanned billing makes the storage duplication cost concrete in dollars
  rather than theoretical
- A 100M+ row test to see whether the join-cost gap widens at larger
  scale, since 5M may still be within the range where DuckDB's join
  performance masks the difference


  