# Project 5 — Snapshotting Architecture


Customer Source System
                   (exposes current state only)
                             │
                       Nightly Poll
                             │
          ┌──────────────────┴──────────────────┐
          │                                     │
  Periodic Snapshot                    Incremental Snapshot
  (full copy, every night,             (hash-diff vs last
   independent of prior state)          successful checkpoint)
          │                                     │
          ▼                                     ▼
 Full Snapshot History              Base Snapshot + Delta History
          │                                     │
          │                          ┌──────────┴──────────┐
          │                          │                     │
          │                   Checkpoint Tracking    Idempotent Retry
          │                   (checkpoint_night in    (safe to rerun a
          │                    job history; stalls     failed job any
          │                    on failure, jumps        number of times
          │                    forward on recovery)     via upsert)
          │                          │                     │
          └──────────────┬───────────┴─────────────────────┘
                          ▼
                Historical Reconstruction
                ("what was true on Night N?")
                          │
                          ▼
                 Validation Gate
      (row count · duplicates · checksum · delta anomaly)
                          │
                          ▼
              Trusted for Downstream Use


## Key Components

**Snapshot** — a captured copy of dimension state at a point in time.
Periodic captures everything, every time. Incremental captures only
what changed since the last trusted state.

**Delta** — the set of rows an incremental snapshot actually writes:
only customers whose attribute hash differs from the last checkpoint.

**Checkpoint** — the operational fact of "which night's state can I
currently trust as my comparison baseline." Distinct from the calendar
night label — a failed job means the checkpoint stalls even though the
calendar keeps moving.

**Idempotent Retry** — a job designed so that running it once, twice,
or ten times in a row produces the same final state. Achieved here via
an upsert (`ON CONFLICT DO UPDATE`) keyed on the natural identity of a
delta row (`customer_id`, `night_number`).

**Validation Gate** — the set of checks run against a pipeline's output
before it's trusted downstream, standing in for the ground truth a
real production system never has: row count sanity, duplicate
detection, checksum reconciliation against an independent source, and
statistical anomaly detection on delta size.

**Recovery** — using `checkpoint_night` (not raw `night_number`) to
answer "what's the latest state I can safely reconstruct as of a given
point," so a failed night degrades gracefully into "slightly stale but
known-correct" rather than silently wrong.