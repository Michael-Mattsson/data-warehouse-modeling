-- =============================================================================
-- Snapshotting — History Builder (Reference SQL)
-- =============================================================================
-- Core distinction from Project 3: SCD Type 2 is built when the source
-- system tells you when a change happened. Snapshotting shows current state
-- each time you poll, and history must be inferred by diffing snapshots taken
-- at each poll. This changes the failure modes: a missed poll in an SCD2 pipeline
-- means a late-arriving event; a missed poll in a snapshot pipeline means a gap
-- in your ability to say what the state was on that specific night, permanently.
--
-- Note: this file is a reference — build_snapshot_history.py is what actually
-- runs. Placeholders (:target_night, :night_number, etc.) represent Python
-- variables substituted at execution time, and true_nightly_state_for_this_night
-- represents the DataFrame returned by the true_state_at_night() Python helper
-- for whichever night is currently being processed, not a real persisted table.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- True nightly state — ground truth, used to drive the simulation and
-- later verify reconstruction. Real pollers never have access to this;
-- it exists here purely so this project can check its own correctness.
-- -----------------------------------------------------------------------------

WITH ranked_changes AS (
    SELECT
        customer_id, new_region, new_country, new_segment,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id ORDER BY night_number DESC
        ) AS rn
    FROM change_log
    WHERE night_number <= :target_night
),
latest_change AS (
    SELECT customer_id, new_region, new_country, new_segment
    FROM ranked_changes WHERE rn = 1
)
SELECT
    b.customer_id,
    COALESCE(lc.new_region,  b.region)  AS region,
    COALESCE(lc.new_country, b.country) AS country,
    COALESCE(lc.new_segment, b.segment) AS segment
FROM customer_baseline b
LEFT JOIN latest_change lc ON b.customer_id = lc.customer_id;


-- -----------------------------------------------------------------------------
-- Job history table
--
-- checkpoint_night is the key new concept: for incremental jobs, it's the
-- night whose state is now the trusted comparison baseline. It only
-- advances on success. Watching it stall during Night 12's failure and
-- jump by 2 at Night 13 (11 -> 13, never landing on 12) is the clearest
-- way to see the defensive design in action.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE snapshot_job_history (
    job_id           INTEGER,
    night_number     INTEGER,
    snapshot_type    VARCHAR,
    status           VARCHAR,
    rows_processed   INTEGER,
    checkpoint_night INTEGER,   -- NULL for periodic; meaningful for incremental
    started_at       TIMESTAMP,
    finished_at      TIMESTAMP
);

-- Log a periodic job run (success or failure). checkpoint_night is always
-- NULL for periodic, since each periodic snapshot stands alone.
INSERT INTO snapshot_job_history
VALUES (:job_id, :night_number, 'periodic', :status, :rows_processed,
        NULL, :started_at, :finished_at);

-- Log an incremental job run. On success, checkpoint_night = night_number.
-- On failure, checkpoint_night is whatever the last successful value was —
-- this is tracked in Python (last_successful_checkpoint), not computed in
-- SQL, since it depends on execution history across runs, not on data alone.
INSERT INTO snapshot_job_history
VALUES (:job_id, :night_number, 'incremental', :status, :rows_processed,
        :checkpoint_night, :started_at, :finished_at);


-- -----------------------------------------------------------------------------
-- Periodic snapshot — full copy, every night, independent of prior nights.
-- Night 12 deliberately skipped (simulated job failure).
-- -----------------------------------------------------------------------------

INSERT INTO periodic_snapshots
SELECT :night_number AS night_number, customer_id, region, country, segment
FROM true_nightly_state_for_this_night;


-- -----------------------------------------------------------------------------
-- Incremental snapshot — defensive design.
-- Diffs against tracking_state (the last SUCCESSFULLY captured state),
-- not against "night_number - 1" specifically. This is what allows the
-- process to correctly absorb a skipped night's changes into the next
-- successful night's delta rather than losing them.
-- -----------------------------------------------------------------------------

-- Detect changes since last successful capture
SELECT t.customer_id, t.region, t.country, t.segment
FROM true_nightly_state_for_this_night t
JOIN tracking_state ts ON t.customer_id = ts.customer_id
WHERE MD5(CONCAT_WS('|', t.region, t.country, t.segment))
   != MD5(CONCAT_WS('|', ts.region, ts.country, ts.segment));

-- Update tracking_state to reflect this successful capture
UPDATE tracking_state
SET region = t.region, country = t.country, segment = t.segment
FROM true_nightly_state_for_this_night t
WHERE tracking_state.customer_id = t.customer_id;