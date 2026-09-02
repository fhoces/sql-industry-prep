-- =============================================================================
-- Module 2: JOINs
-- =============================================================================

.headers on
.mode column

-- -----------------------------------------------------------------------------
-- Q1. Unique drivers per rider (top 10 most-diverse riders)
-- -----------------------------------------------------------------------------
SELECT req.rider_id,
       COUNT(DISTINCT r.driver_id) AS n_unique_drivers,
       COUNT(*)                    AS n_rides
FROM   rides r
JOIN   requests req ON r.request_id = req.request_id
GROUP BY req.rider_id
ORDER BY n_unique_drivers DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q2. Drivers who NEVER accepted a request from a majority-minority
--     neighborhood (pct_minority >= 0.8; at 0.5 the result is empty --
--     every driver has at least one such pickup)
-- -----------------------------------------------------------------------------
SELECT d.driver_id, d.gender
FROM   drivers d
WHERE  NOT EXISTS (
  SELECT 1
  FROM   rides r
  JOIN   requests req ON r.request_id = req.request_id
  JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  WHERE  r.driver_id = d.driver_id
    AND  n.pct_minority >= 0.8
)
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q3. Each ride attached to the driver's tenure (days since signup)
-- -----------------------------------------------------------------------------
SELECT r.ride_id,
       r.driver_id,
       d.signup_date,
       date(r.started_at) AS ride_date,
       julianday(r.started_at) - julianday(d.signup_date) AS tenure_days
FROM   rides r
JOIN   drivers d ON r.driver_id = d.driver_id
ORDER BY r.ride_id
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q4. Rider-driver pairs with 2+ five-star ratings together
-- -----------------------------------------------------------------------------
SELECT req.rider_id,
       r.driver_id,
       COUNT(*) AS n_5star
FROM   rides r
JOIN   requests req ON r.request_id = req.request_id
WHERE  r.rider_rating = 5
GROUP BY req.rider_id, r.driver_id
HAVING COUNT(*) >= 2
ORDER BY n_5star DESC
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Q5. City-by-city ride count plus lead PM
-- -----------------------------------------------------------------------------
SELECT c.name AS city,
       c.lead_pm,
       COUNT(*) AS n_rides,
       ROUND(AVG(r.fare_usd), 2) AS avg_fare
FROM   rides r
JOIN   requests req ON r.request_id = req.request_id
JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN   cities c ON n.city_id = c.city_id
GROUP BY c.name, c.lead_pm
ORDER BY n_rides DESC;


-- -----------------------------------------------------------------------------
-- Q6. Anti-join example: requests that were NOT accepted
-- -----------------------------------------------------------------------------
SELECT req.request_id, req.rider_id, req.requested_at
FROM   requests req
LEFT JOIN rides r ON req.request_id = r.request_id
WHERE  r.ride_id IS NULL
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q7. Share of unaccepted requests per city (LEFT JOIN + NULL counting)
-- -----------------------------------------------------------------------------
SELECT c.name AS city,
       COUNT(*) AS n_requests,
       SUM(CASE WHEN r.ride_id IS NULL THEN 1 ELSE 0 END) AS n_unaccepted,
       ROUND(1.0 * SUM(CASE WHEN r.ride_id IS NULL THEN 1 ELSE 0 END)
               / COUNT(*), 3) AS pct_unaccepted
FROM   requests req
LEFT JOIN rides r      ON req.request_id = r.request_id
JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN   cities c        ON n.city_id = c.city_id
GROUP BY c.name
ORDER BY pct_unaccepted DESC;


-- -----------------------------------------------------------------------------
-- Q8. Self-join: hours since the driver's previous ride ended
--     (window-function version in Module 5: LAG(ended_at) OVER (...))
-- -----------------------------------------------------------------------------
SELECT r1.ride_id, r1.driver_id, r1.started_at,
       MAX(r2.ended_at) AS prev_ride_ended,
       ROUND((julianday(r1.started_at) - julianday(MAX(r2.ended_at))) * 24, 1)
         AS hours_since_prev
FROM   rides r1
LEFT JOIN rides r2
  ON   r1.driver_id  = r2.driver_id
  AND  r2.started_at < r1.started_at
GROUP BY r1.ride_id
LIMIT 10;


