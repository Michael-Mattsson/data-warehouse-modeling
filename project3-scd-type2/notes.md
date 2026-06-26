# SCD Type 2 — Design Notes and Key Findings

## What this project demonstrates

A slowly changing dimension (SCD) tracks how an entity's attributes
change over time. Type 2 preserves full history by inserting a new row
on each change rather than overwriting the existing one. This enables
point-in-time reconstruction — answering "what was true at the time?"
rather than only "what is true now?"

Without Type 2, every historical query implicitly uses the customer's
current attributes. Revenue by region, segment analysis, and cohort
tracking all silently produce wrong results when customers move or
change classification over time.

---

## The two-step change operation

Every SCD Type 2 change follows the same pattern:

1. Close the current record: set valid_to = change_date - 1, is_current = FALSE
2. Insert a new record: valid_from = change_date, valid_to = NULL, is_current = TRUE

The valid_to on the closed record is set to change_date - 1 (not
change_date) so that the ranges are non-overlapping with no gaps.
An order placed on the exact change_date matches the new record only.

---

## The correct temporal join

```sql
JOIN dim_customer_scd2 c
    ON  o.customer_id  = c.customer_id
    AND o.order_date  >= c.valid_from
    AND (o.order_date  < c.valid_to OR c.valid_to IS NULL)
```

The NULL check on valid_to is not optional. Active records have
valid_to = NULL. A join condition of `o.order_date < c.valid_to`
alone would exclude all current records, returning no matches for
orders placed after the last change.

---

## The failure mode: omitting date bounds

Joining on customer_id alone returns one row per SCD2 version per order.
A customer with N versions produces N rows per order in the join result.

At this dataset's change rate (4 changes across ~10,000 customers):
- Aggregate revenue inflation is small — under 0.1%
- For the three specific changed customers, inflation is exactly 2x or 3x
- In production with thousands of changes, the aggregate inflation
  becomes significant and difficult to detect without a known baseline

The inflation quantification query (Q5 in point_in_time_queries.sql)
demonstrates this precisely for customers 1001, 2500, and 5000.

---

## Scenarios simulated

| Customer | Change           | Effective Date | SCD2 Versions |
|----------|------------------|----------------|---------------|
| 1001     | Region/country   | 2023-03-01     | 2             |
| 2500     | Segment upgrade  | 2023-06-15     | 2             |
| 5000     | Segment (×2)     | 2022-09-01, 2023-05-01 | 3   |

Customer 5000 (3 versions) is the most important test case — it
produces 3x row duplication in the broken join and makes the failure
mode unambiguous in the output.

---

## Connection to Project 2

Project 2's schema evolution test showed that wide tables require
5,000,000-row backfills for dimension attribute changes. Type 2 adds
a second reason why wide tables are incompatible with production
requirements: a wide table cannot represent a customer's historical
region alongside their current region without either duplicating
fact rows per version or embedding the full SCD2 logic into the
fact table itself — both of which defeat the purpose of denormalization.

The star schema's separation of fact and dimension tables is what makes
Type 2 possible without touching fct_orders at all.

---

## Connection to Project 3 and beyond

Project 4 (metric inflation) will demonstrate the same row duplication
problem from a different cause: many-to-many joins rather than missing
temporal bounds. The diagnostic pattern is identical — compare row counts
before and after the join, then quantify the inflation against a known
baseline.