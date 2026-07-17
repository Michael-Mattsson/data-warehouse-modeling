-- =============================================================================
-- Checkpoint Metadata — Reference SQL
-- =============================================================================
-- Queries against snapshot_job_history. No simulation happens here —
-- see build_snapshot_history.py for how the table is populated.
-- =============================================================================

-- Full checkpoint evolution
SELECT night_number, status, rows_processed, checkpoint_night
FROM snapshot_job_history
WHERE snapshot_type = 'incremental'
ORDER BY night_number;

-- The recovery pattern: safe checkpoint to use for any target night
SELECT MAX(checkpoint_night) AS safe_checkpoint_to_use
FROM snapshot_job_history
WHERE snapshot_type = 'incremental'
  AND status = 'success'
  AND checkpoint_night <= :target_night;