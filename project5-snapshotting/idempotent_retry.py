import duckdb
import pandas as pd

# ---------------------------------------------------------------------------
# Idempotent Retry — Why Retries Are Dangerous
#
# Connects to the Stripe idempotency pattern: "the call could succeed, but
# the connection break before the server can tell its client about it."
# Applied here to a batch job instead of an API call — same failure mode,
# same fix.
#
# This file does not touch the official incremental_deltas table built by
# build_snapshot_history.py. It's a self-contained demonstration using
# already-established ground truth (periodic_snapshots Night 11, and
# change_log) as inputs, simulating what happens if ops manually retries
# the failed Night 12 job.

# Scenario 1: Normal load — retry runs once, correctly.
# Scenario 2: Retry — an orchestrator double-trigger (job succeeded, but
#             the "job complete" acknowledgment was lost, so the scheduler
#             reruns it) causes the naive retry script to insert the same
#             rows twice.
# Scenario 3: MERGE / idempotent upsert — rerunning any number of times
#             converges to the same correct state.
# ---------------------------------------------------------------------------

DB_PATH = "../small-systems-projects/data/project5_snapshots.duckdb"
con = duckdb.connect(DB_PATH)
pd.set_option("display.width", 120)


def true_state_at_night(con, night_number):
    return con.execute(f"""
        WITH ranked_changes AS (
            SELECT customer_id, new_region, new_country, new_segment,
                   ROW_NUMBER() OVER (
                       PARTITION BY customer_id ORDER BY night_number DESC
                   ) AS rn
            FROM change_log WHERE night_number <= {night_number}
        ),
        latest_change AS (
            SELECT customer_id, new_region, new_country, new_segment
            FROM ranked_changes WHERE rn = 1
        )
        SELECT b.customer_id,
               COALESCE(lc.new_region,  b.region)  AS region,
               COALESCE(lc.new_country, b.country) AS country,
               COALESCE(lc.new_segment, b.segment) AS segment
        FROM customer_baseline b
        LEFT JOIN latest_change lc ON b.customer_id = lc.customer_id
    """).fetchdf()


def compute_changed_rows(con, night_target, night_baseline):
    """The detection logic a Night 12 retry job would run: diff current
    true state against the last trusted checkpoint (Night 11)."""
    true_state = true_state_at_night(con, night_target)
    con.register("true_state_df", true_state)
    changed = con.execute(f"""
        SELECT t.customer_id, t.region, t.country, t.segment
        FROM true_state_df t
        JOIN periodic_snapshots b
            ON t.customer_id = b.customer_id AND b.night_number = {night_baseline}
        WHERE MD5(CONCAT_WS('|', t.region, t.country, t.segment))
           != MD5(CONCAT_WS('|', b.region, b.country, b.segment))
    """).fetchdf()
    con.unregister("true_state_df")
    return changed


# ---------------------------------------------------------------------------
# Scenario 1: Normal load — retry Night 12's job, once, correctly
# ---------------------------------------------------------------------------

print(f"\n{'='*70}")
print("  Scenario 1: Normal Load — Night 12 Retry (Single Run)")
print(f"{'='*70}")

con.execute("""
CREATE OR REPLACE TABLE retry_deltas (
    customer_id INTEGER, night_number INTEGER,
    region VARCHAR, country VARCHAR, segment VARCHAR
)
""")

changed_rows = compute_changed_rows(con, night_target=12, night_baseline=11)
con.register("changed_df", changed_rows)
con.execute("""
    INSERT INTO retry_deltas
    SELECT customer_id, 12 AS night_number, region, country, segment
    FROM changed_df
""")
con.unregister("changed_df")

count_after_scenario1 = con.execute("SELECT COUNT(*) FROM retry_deltas").fetchone()[0]
print(f"  Delta rows written for Night 12: {count_after_scenario1}")
print(f"  This is the correct, expected size — a handful of rows, matching")
print(f"  the change rate seen on every other successful night.")


# ---------------------------------------------------------------------------
# Scenario 2: Retry causes duplicates
#
# The orchestrator believes the job never completed (ack was lost) and
# reruns it. The retry script is naive: it recomputes the same changed
# rows and blindly INSERTs them again, with no check for whether a row
# for this (customer_id, night_number) already exists.
# ---------------------------------------------------------------------------

print(f"\n{'='*70}")
print("  Scenario 2: Retry — Naive Re-run Creates Duplicates")
print(f"{'='*70}")

changed_rows_again = compute_changed_rows(con, night_target=12, night_baseline=11)
con.register("changed_df2", changed_rows_again)
con.execute("""
    INSERT INTO retry_deltas
    SELECT customer_id, 12 AS night_number, region, country, segment
    FROM changed_df2
""")
con.unregister("changed_df2")

count_after_scenario2 = con.execute("SELECT COUNT(*) FROM retry_deltas").fetchone()[0]
duplicates = con.execute("""
    SELECT COUNT(*) FROM (
        SELECT customer_id, night_number FROM retry_deltas
        GROUP BY customer_id, night_number HAVING COUNT(*) > 1
    )
""").fetchone()[0]

print(f"  Delta rows after naive retry: {count_after_scenario2} "
      f"(was {count_after_scenario1} before the retry)")
print(f"  Duplicated (customer_id, night_number) pairs: {duplicates}")
print(f"  A downstream reconstruction query summing or counting from this")
print(f"  table will double-count every affected customer for Night 12 —")
print(f"  structurally identical to Project 4's join inflation, but caused")
print(f"  by an unsafe retry instead of a missing grain guard.")


# ---------------------------------------------------------------------------
# Scenario 3: Idempotent upsert — safe to retry any number of times
#
# DuckDB doesn't require MERGE INTO syntax specifically for this — an
# INSERT ... ON CONFLICT DO UPDATE against a table with a uniqueness
# constraint on (customer_id, night_number) achieves the same idempotent
# semantics. WHEN MATCHED -> update (here, effectively a no-op re-write
# of identical values). WHEN NOT MATCHED -> insert.
# ---------------------------------------------------------------------------

print(f"\n{'='*70}")
print("  Scenario 3: Idempotent Upsert — Safe to Retry")
print(f"{'='*70}")

con.execute("""
CREATE OR REPLACE TABLE retry_deltas_idempotent (
    customer_id INTEGER, night_number INTEGER,
    region VARCHAR, country VARCHAR, segment VARCHAR,
    PRIMARY KEY (customer_id, night_number)
)
""")

def idempotent_retry_job():
    """Simulates the retry job, rewritten to be safe to run any number
    of times. Uses ON CONFLICT as DuckDB's upsert mechanism — the
    conceptual equivalent of MERGE INTO ... WHEN MATCHED THEN UPDATE
    ... WHEN NOT MATCHED THEN INSERT."""
    changed = compute_changed_rows(con, night_target=12, night_baseline=11)
    con.register("changed_df3", changed)
    con.execute("""
        INSERT INTO retry_deltas_idempotent
        SELECT customer_id, 12 AS night_number, region, country, segment
        FROM changed_df3
        ON CONFLICT (customer_id, night_number) DO UPDATE SET
            region  = EXCLUDED.region,
            country = EXCLUDED.country,
            segment = EXCLUDED.segment
    """)
    con.unregister("changed_df3")

idempotent_retry_job()
count_run1 = con.execute("SELECT COUNT(*) FROM retry_deltas_idempotent").fetchone()[0]
print(f"  Row count after 1st run: {count_run1}")

idempotent_retry_job()
count_run2 = con.execute("SELECT COUNT(*) FROM retry_deltas_idempotent").fetchone()[0]
print(f"  Row count after 2nd run (retry): {count_run2}")

idempotent_retry_job()
count_run3 = con.execute("SELECT COUNT(*) FROM retry_deltas_idempotent").fetchone()[0]
print(f"  Row count after 3rd run (another retry): {count_run3}")

print(f"\n  Row count stayed at {count_run1} across all three runs.")
print(f"  This is what 'safe to retry any number of times' actually means —")
print(f"  not that retries never happen, but that their effect converges")
print(f"  to the same state regardless of how many times they occur.")

print("\nIdempotent retry demonstration complete.")
con.close()