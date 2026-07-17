-- =============================================================================
-- Pipeline Validation — Reference SQL
-- =============================================================================

-- 1. Row count sanity
SELECT night_number, COUNT(*) AS delta_size
FROM incremental_deltas GROUP BY night_number
ORDER BY delta_size DESC;

-- 2. Duplicate detection
SELECT customer_id, night_number, COUNT(*) AS occurrences
FROM incremental_deltas
GROUP BY customer_id, night_number
HAVING COUNT(*) > 1;

-- 3. Checksum comparison (order-independent, via SUM of row hashes)
SELECT SUM(HASH(customer_id, region, country, segment)) AS checksum
FROM periodic_snapshots WHERE night_number = 20;

-- 4. Delta size anomaly — flag any night > 5x the historical average
WITH delta_sizes AS (
    SELECT night_number, COUNT(*) AS cnt FROM incremental_deltas GROUP BY night_number
),
stats AS (SELECT AVG(cnt) AS avg_delta FROM delta_sizes)
SELECT d.night_number, d.cnt, s.avg_delta
FROM delta_sizes d, stats s
WHERE d.cnt > s.avg_delta * 5;