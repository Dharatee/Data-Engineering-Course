-- week3_reliability.sql
-- Week 3 Assignment
-- Submit TWO files:
--   1. week3_reliability.sql  (this file — SQL tasks)
--   2. transactional_loader.py (Python task — Q5)
--
-- All SQL runs against the normalized schema from Week 2
-- (drivers, riders, locations, trips)

-- ─────────────────────────────────────────────────────────────────
-- Q1: Add indexes to the trips table
--
-- Before adding ANY index, run EXPLAIN ANALYZE on each query below
-- and record the execution time in a comment.
-- Then add your indexes and run EXPLAIN ANALYZE again.
-- The comparison IS the answer — not just the CREATE INDEX statement.
-- ─────────────────────────────────────────────────────────────────

-- Baseline queries — run EXPLAIN ANALYZE on each BEFORE indexing:

-- Query A: filter by driver
---- BEFORE CREATING INDEX

EXPLAIN ANALYZE
SELECT 
    * 
FROM 
    trips 
WHERE 
    driver_id = 3;

-- Seq Scan on trips  (cost=0.00..132.50 rows=481 width=85) (actual time=0.027..1.041 rows=481 loops=1)
-- Filter: (driver_id = 3)
-- Rows Removed by Filter: 4519
-- Planning Time: 0.083 ms
-- Execution Time: 1.089 ms

----- AFTER CREATING INDEX

CREATE INDEX index_trips_driver_id ON trips(driver_id);
 
EXPLAIN ANALYZE
SELECT 
    * 
FROM 
    trips 
WHERE 
    driver_id = 3;


-- Bitmap Heap Scan on trips  (cost=8.01..84.02 rows=481 width=85) (actual time=0.198..0.427 rows=481 loops=1)
-- Recheck Cond: (driver_id = 3)
-- Heap Blocks: exact=69
--->Bitmap Index Scan on index_trips_driver_id  (cost=0.00..7.89 rows=481 width=0) (actual time=0.185..0.186 rows=481 loops=1)
-- Index Cond: (driver_id = 3)
-- Planning Time: 0.193 ms
-- Execution Time: 0.490 ms



-- Query B: filter by status
------- BEFORE CREATING INDEX
EXPLAIN ANALYZE
SELECT 
    * 
FROM 
    trips 
WHERE 
    status = 'cancelled';

-- Seq Scan on trips  (cost=0.00..132.50 rows=1408 width=85) (actual time=0.015..1.420 rows=1408 loops=1)
-- Filter: ((status)::text = 'cancelled'::text)
-- Rows Removed by Filter: 3592
-- Planning Time: 0.093 ms
-- Execution Time: 1.528 ms


-------AFTER CREATING INDEX
CREATE INDEX index_trips_status ON trips(status);
 
EXPLAIN ANALYZE
  SELECT 
    * 
FROM 
    trips 
WHERE 
    status = 'cancelled';


-- Bitmap Heap Scan on trips  (cost=19.19..106.79 rows=1408 width=85) (actual time=0.128..0.435 rows=1408 loops=1)
-- Recheck Cond: ((status)::text = 'cancelled'::text)
-- Heap Blocks: exact=70
--->Bitmap Index Scan on indx_trips_status  (cost=0.00..18.84 rows=1408 width=0) (actual time=0.108..0.109 rows=1408 loops=1)
-- Index Cond: ((status)::text = 'cancelled'::text)
-- Planning Time: 0.389 ms
-- Execution Time: 0.552 ms



-- Query C: filter by driver AND status (common in the pipeline)
-----BEFORE CREATING INDEX
EXPLAIN ANALYZE
SELECT 
    * 
FROM 
    trips 
WHERE 
    driver_id = 3 AND status = 'completed';


-- Seq Scan on trips  (cost=19.19..139.77 rows=1408 width=85) (actual time=0.015..1.465 rows=1408 loops=1)
-- Filter: ((status)::text = 'completed'::text)
-- Rows Removed by Filter: 3592
-- Planning Time: 0.098 ms
-- Execution Time: 1.635 ms


-------- AFTER CREATING INDEX
CREATE INDEX index_trips_driver_id_status ON trips(driver_id, status)
SELECT 
    * 
FROM 
    trips 
WHERE 
    driver_id = 3 AND status = 'completed';


-- Bitmap Heap Scan on trips  (cost=7.10..81.23 rows=275 width=85) (actual time=0.049..0.153 rows=284 loops=1)
-- Recheck Cond: ((driver_id = 3) AND ((status)::text = 'completed'::text))
-- Heap Blocks: exact=66
---> Bitmap Index Scan on indx_trips_driver_status  (cost=0.00..7.03 rows=275 width=0) (actual time=0.031..0.032 rows=284 loops=1)
-- Index Cond: ((driver_id = 3) AND ((status)::text = 'completed'::text))
-- Planning Time: 0.114 ms
-- Execution Time: 0.194 ms




-- ─────────────────────────────────────────────────────────────────
-- Q2: Create completed_trips_view
--
-- Must return only completed trips with ALL of these columns:
--   trip_id, driver_name, rider_name,
--   pickup_city, dropoff_city,
--   fare_amount, distance_km, rating,
--   payment_method, requested_at, completed_at
--
-- No IDs in the output — use JOINs to resolve all foreign keys.
-- ─────────────────────────────────────────────────────────────────


CREATE VIEW completed_trips_detailed_view AS 
SELECT 
    t.trip_id,
    d.name AS driver_name,
    p.name AS passenger_name,
    pck.city_name AS pickup_city,
    dst.city_name AS dropoff_city,
    t.fare_amount,
    t.distance_km,
    t.rating,
    t.payment_method_id,
    t.requested_at,
    t.completed_at
FROM 
    trips t
INNER JOIN 
    drivers d
ON 
    t.driver_id = d.driver_id
INNER JOIN 
    passengers p
ON 
    t.passenger_id  = p.passenger_id
INNER JOIN 
    locations pck
ON 
    t.pickup_location_id = pck.location_id
INNER JOIN 
    locations dst
ON 
    t.dropoff_location_id = dst.location_id
WHERE 
    t.status = 'completed';



--- For verificcation---
SELECT 
    * 
FROM 
    completed_trips_detailed_view LIMIT 5;


SELECT 
    COUNT(*) 
FROM 
    completed_trips_detailed_view;
--- Output: 2862



-- ─────────────────────────────────────────────────────────────────
-- Q3: Create driver_summary view
--
-- Must show one row per driver with:
--   driver_name
--   total_trips          (all statuses)
--   completed_trips
--   cancelled_trips
--   cancellation_rate    (cancelled / total * 100, rounded to 1dp)
--   avg_fare             (completed trips only, rounded to 2dp)
--   avg_rating           (completed trips only, rounded to 1dp)
--
-- Challenge: use COUNT(*) FILTER (WHERE ...) instead of CASE WHEN
-- ─────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS driver_summary;

CREATE VIEW driver_summary AS
SELECT
    d.name AS driver_name,
    COUNT(t.trip_id) AS total_trips,
    COUNT(*) FILTER (WHERE t.status = 'completed') AS completed_trips,
    COUNT(*) FILTER (WHERE t.status = 'cancelled') AS cancelled_trips,
    ROUND(
        COUNT(*) FILTER (WHERE t.status = 'cancelled') * 100.0
        / NULLIF(COUNT(t.trip_id), 0),
        1
    ) AS cancellation_rate,
    ROUND(
        AVG(t.fare_amount) FILTER (WHERE t.status = 'completed'),
        2
    ) AS avg_fare,
    ROUND(
        AVG(t.rating) FILTER (WHERE t.status = 'completed'),
        1
    ) AS avg_rating
FROM 
    drivers d
LEFT JOIN 
    trips t
ON 
    d.driver_id = t.driver_id
GROUP BY 
    d.driver_id, d.name;


-- For Verifications
SELECT 
    *
FROM 
    driver_summary
ORDER BY 
    completed_trips DESC;



-- ─────────────────────────────────────────────────────────────────
-- Q4: Transaction with intentional failure
--
-- Write a transaction that:
--   1. Inserts a new driver named 'Test Driver'
--   2. Inserts 3 valid trips for that driver
--   3. Inserts a 4th trip with rating = 99 (violates CHECK constraint)
--
-- The entire transaction should roll back.
-- Verify with: SELECT * FROM drivers WHERE name = 'Test Driver';
-- Expected: 0 rows (atomicity — nothing committed)
-- ─────────────────────────────────────────────────────────────────

-- Delete any existing 'Test Driver' rows to ensure a clean slate for the transaction

DELETE FROM 
    drivers
WHERE 
    name = 'Test Driver';


BEGIN;

-- 1. Insert new driver
INSERT INTO drivers (name)
VALUES ('Test Driver');

-- 2. Insert 3 valid trips
INSERT INTO trips (
    driver_id,
    passenger_id,
    pickup_location_id,
    dropoff_location_id,
    fare_amount,
    distance_km,
    status,
    requested_at,
    completed_at,
    rating,
    payment_method_id
)
VALUES
	((SELECT driver_id FROM drivers WHERE name = 'Test Driver' ORDER BY driver_id DESC LIMIT 1),
    1, 1, 2, 250.00, 8.5, 'completed','2025-01-15 09:00:00', '2025-01-15 09:35:00', 4.5, 1),
    ((SELECT driver_id FROM drivers WHERE name = 'Test Driver' ORDER BY driver_id DESC LIMIT 1),
    4, 2, 3, 300.00, 10.2, 'completed', '2025-01-15 10:00:00', '2025-01-15 10:45:00', 4.0, 2),
    ((SELECT driver_id FROM drivers WHERE name = 'Test Driver' ORDER BY driver_id DESC LIMIT 1),
    2, 3, 4, 180.00, 5.7, 'completed', '2025-01-15 11:00:00', '2025-01-15 11:25:00', 5.0, 3);


-- 3. Insert invalid trip: rating = 99 should fail
INSERT INTO trips (
    driver_id,
    passenger_id,
    pickup_location_id,
    dropoff_location_id,
    fare_amount,
    distance_km,
    status,
    requested_at,
    completed_at,
    rating,
    payment_method_id
)
VALUES (
    (SELECT driver_id FROM drivers WHERE name = 'Test Driver' ORDER BY driver_id DESC LIMIT 1),
    1, 1, 2, 500.00, 12.0, 'completed', '2025-01-15 12:00:00', '2025-01-15 12:40:00', 99, 2);

COMMIT;

-- ERROR: numeric field overflow
-- Detail: A field with precision 2, scale 1 must round to an absolute value less than 10^1.


ROLLBACK;

-- Verification query:

SELECT
    'drivers' AS tbl,
    COUNT(*) AS test_driver_rows
FROM drivers
WHERE name = 'Test Driver'
UNION ALL
SELECT 'trips', COUNT(*)
FROM trips t
JOIN drivers d ON t.driver_id = d.driver_id
WHERE d.name = 'Test Driver';

-- Output:: drivers/trips : 0 / 0


-- ─────────────────────────────────────────────────────────────────
-- Q6 (STRETCH): Window function — running total fare per driver
--
-- For each completed trip, show:
--   trip_id, driver_name, requested_at, fare_amount,
--   running_total_fare (driver's cumulative fare up to this trip)
--
-- Use: SUM(fare_amount) OVER (PARTITION BY driver_id ORDER BY requested_at)
-- Order the final output by driver_name, requested_at
-- ─────────────────────────────────────────────────────────────────

SELECT
    t.trip_id,
    d.name AS driver_name,
    t.requested_at,
    t.fare_amount,
    SUM(t.fare_amount) OVER (PARTITION BY t.driver_id ORDER BY t.requested_at) AS running_total_fare
FROM trips t
JOIN drivers d
    ON t.driver_id = d.driver_id
WHERE t.status = 'completed'
ORDER BY
    driver_name,
    t.requested_at;