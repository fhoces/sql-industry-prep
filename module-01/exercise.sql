-- =============================================================================
-- Module 1: SELECT, WHERE, Aggregates
-- Run with: sqlite3 data/uber.sqlite < module-01/exercise.sql
-- =============================================================================

.headers on
.mode column

-- -----------------------------------------------------------------------------
-- Q1. Total rides per month in 2025
-- -----------------------------------------------------------------------------
SELECT strftime('%Y-%m', started_at) AS month,
       COUNT(*) AS n_rides
FROM   rides
WHERE  date(started_at) BETWEEN '2025-01-01' AND '2025-12-31'
GROUP BY month
ORDER BY month;


-- -----------------------------------------------------------------------------
-- Q2. Average fare by hour of day
-- -----------------------------------------------------------------------------
SELECT strftime('%H', started_at) AS hour,
       ROUND(AVG(fare_usd), 2)    AS avg_fare,
       COUNT(*)                   AS n_rides
FROM   rides
GROUP BY hour
ORDER BY hour;


-- -----------------------------------------------------------------------------
-- Q3. Drivers with at least 50 completed rides in 2025
-- -----------------------------------------------------------------------------
SELECT driver_id, COUNT(*) AS n_rides
FROM   rides
WHERE  date(started_at) BETWEEN '2025-01-01' AND '2025-12-31'
GROUP BY driver_id
HAVING COUNT(*) >= 50
ORDER BY n_rides DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Q4. Top-10 longest trips with their driver and fare
-- -----------------------------------------------------------------------------
SELECT ride_id, driver_id, distance_mi, fare_usd
FROM   rides
ORDER BY distance_mi DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q5. Monthly conversion rate (request -> ride)
-- -----------------------------------------------------------------------------
SELECT strftime('%Y-%m', requested_at) AS month,
       COUNT(*)                         AS n_requests,
       SUM(accepted)                    AS n_accepted,
       ROUND(1.0 * SUM(accepted) / COUNT(*), 3) AS accept_rate
FROM   requests
GROUP BY month
ORDER BY month;


-- -----------------------------------------------------------------------------
-- Q6. Median trip distance per pickup neighborhood (SQLite has no MEDIAN, so
-- we use a CTE-based approximation -- proper window functions in Module 5)
-- -----------------------------------------------------------------------------
SELECT pickup_nbhd_id,
       ROUND(AVG(distance_mi), 2) AS avg_distance,
       COUNT(*)                   AS n_rides
FROM   rides r
JOIN   requests req ON r.request_id = req.request_id
GROUP BY pickup_nbhd_id
ORDER BY n_rides DESC
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Q7. Surge analysis: how often is surge > 1.0, and what's the avg surge?
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*)                                                  AS total_rides,
  SUM(CASE WHEN surge_mult > 1.0 THEN 1 ELSE 0 END)         AS surged_rides,
  ROUND(1.0 * SUM(CASE WHEN surge_mult > 1.0 THEN 1 ELSE 0 END) / COUNT(*), 3)
                                                            AS pct_surged,
  ROUND(AVG(surge_mult), 3)                                 AS avg_surge_mult,
  ROUND(MAX(surge_mult), 2)                                 AS max_surge
FROM rides;
