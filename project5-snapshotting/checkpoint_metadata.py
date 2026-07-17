import duckdb
import pandas as pd

# ---------------------------------------------------------------------------
# Checkpoint Metadata — Observability Report
#
# Production pipelines store information ABOUT the pipeline, not just the
# data itself. This file queries snapshot_job_history (built by
# build_snapshot_history.py) to surface the checkpoint concept explicitly —
# it does not resimulate any jobs.
#
# Checkpoint vs night_number: night_number is a calendar label. checkpoint
# _night is an operational fact — "as of what point can I trust the
# incremental state." They diverge exactly when a job fails, which is the
# whole point of tracking both.
# ---------------------------------------------------------------------------

DB_PATH = "../small-systems-projects/data/project5_snapshots.duckdb"
con = duckdb.connect(DB_PATH)
pd.set_option("display.width", 120)


def run(label, query):
    print(f"\n{'='*70}")
    print(f"  {label}")
    print(f"{'='*70}")
    print(con.execute(query).fetchdf().to_string(index=False))


# ---------------------------------------------------------------------------
# Step 1: Job history schema — what's tracked
# ---------------------------------------------------------------------------

run("Sample job history rows (nights 9-14)", """
    SELECT job_id, night_number, snapshot_type, status,
           rows_processed, checkpoint_night, started_at, finished_at
    FROM snapshot_job_history
    WHERE night_number BETWEEN 9 AND 14
    ORDER BY night_number, snapshot_type
""")


# ---------------------------------------------------------------------------
# Step 2: Successful incremental jobs — checkpoint advances in lockstep
# ---------------------------------------------------------------------------

run("Incremental successes — checkpoint advances with night_number", """
    SELECT night_number, status, rows_processed, checkpoint_night
    FROM snapshot_job_history
    WHERE snapshot_type = 'incremental' AND status = 'success'
    ORDER BY night_number
    LIMIT 10
""")


# ---------------------------------------------------------------------------
# Step 3: The failed job — checkpoint carries forward, unchanged
# ---------------------------------------------------------------------------

run("The Night 12 failure — checkpoint does NOT advance", """
    SELECT night_number, status, rows_processed, checkpoint_night
    FROM snapshot_job_history
    WHERE snapshot_type = 'incremental' AND night_number IN (11, 12, 13)
    ORDER BY night_number
""")
print("  Night 11 checkpoint = 11 (success). Night 12 checkpoint = 11")
print("  (failure — carried forward, unchanged). Night 13 checkpoint = 13")
print("  (success — jumps by 2, since it correctly diffed against Night 11,")
print("  absorbing any Night 12 changes into Night 13's delta).")


# ---------------------------------------------------------------------------
# Step 4: Full checkpoint evolution across all 30 nights
# ---------------------------------------------------------------------------

run("Checkpoint evolution — full history", """
    SELECT night_number, status, rows_processed, checkpoint_night
    FROM snapshot_job_history
    WHERE snapshot_type = 'incremental'
    ORDER BY night_number
""")


# ---------------------------------------------------------------------------
# Step 5: Recovery — how downstream consumers should use checkpoint_night
#
# A reconstruction query that asks "what was the state as of Night 12"
# should not trust the raw night_number label. It should query the most
# recent successful checkpoint at or before the target night — exactly
# mirroring the "as of" reconstruction pattern already used in
# periodic_vs_incremental.py, but now driven by the job history table
# rather than by manually scanning for gaps.
# ---------------------------------------------------------------------------

run("Recovery pattern — safe 'as of Night 12' lookup via checkpoint metadata", """
    SELECT MAX(checkpoint_night) AS safe_checkpoint_to_use
    FROM snapshot_job_history
    WHERE snapshot_type = 'incremental'
      AND status = 'success'
      AND checkpoint_night <= 12
""")
print("  This is the query a downstream consumer should run before trusting")
print("  any 'as of Night 12' result — it answers 'what is the latest")
print("  checkpoint I can safely rely on at or before Night 12,' rather")
print("  than assuming Night 12's own data exists just because it was asked for.")

print("\nCheckpoint metadata review complete.")
con.close()