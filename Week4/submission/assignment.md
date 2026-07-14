# Week 4 Assignment — Ride-Sharing Warehouse

Complete the tasks below directly in `warehouse.sql` and `etl.py`. Add any
analysis queries and your written answers to this file under the matching
section.

## 1. `warehouse.sql` — add the vehicle dimension

- Create a `dim_vehicle` table (surrogate key `vehicle_key`, natural key
  `vehicle_id`, plus the descriptive vehicle attributes from the OLTP
  `vehicles` table: plate number, make, model, year, color, category,
  is_active).


CREATE TABLE dim_vehicle (
    vehicle_key     SERIAL       PRIMARY KEY,
    vehicle_id      INTEGER      NOT NULL UNIQUE,
    plate_number    VARCHAR(20)  NOT NULL,
    make            VARCHAR(50),
    model           VARCHAR(50),
    year            SMALLINT     CHECK (year > 1980),
    color           VARCHAR(30),
    category        VARCHAR(20),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);



- Add `vehicle_key` and `time_key` columns to `fact_trips`, referencing
  `dim_vehicle(vehicle_key)` and `dim_time(time_key)` respectively.

vehicle_key             INTEGER         REFERENCES dim_vehicle(vehicle_key),
time_key                INTEGER         NOT NULL REFERENCES dim_time(time_key),



- Think about whether each new key should be `NOT NULL` — is `vehicle_id`
  always present on a trip in the OLTP schema? Is a time always known?
  Answer: vehicle_key should be NULL since in OLTP schema, trips.vehicle_id is defined as nullable.
          This means a trip may not have a vehicle assigned, so warehouse should allow vehicle_key to be NULL.

          time_key should be NOT NULL because trips.requested_at in OLTP schema is also NOT NULL.
          This is because every trip has a known request timestamp.






## 2. `etl.py` — implement the remaining dimension + fact columns

- Add `extract_vehicle` / `load_dim_vehicle` following the pattern of the
  existing dimension loaders.

def extract_vehicle(conn):
    extract_vehicle_sql = """
    SELECT
        vehicle_id,
        plate_number,
        make,
        model,
        year,
        color,
        category,
        is_active
    FROM
        vehicles v;
    """
    return extract(conn, extract_vehicle_sql)


def load_dim_vehicle(conn, vehicle_data):
    insert_dim_vehicle_sql = """
 INSERT INTO dim_vehicle
    (vehicle_id, plate_number, make, model, year, color, category, is_active)
    VALUES ( %(vehicle_id)s,
             %(plate_number)s,
             %(make)s,
             %(model)s,
             %(year)s,
             %(color)s,
             %(category)s,
             %(is_active)s
            )
    ON CONFLICT (vehicle_id) DO NOTHING
"""
    try:
        with conn.cursor() as curr:
            curr.executemany(insert_dim_vehicle_sql, vehicle_data)
            logger.info(f"{curr.rowcount} inserted to dim_vehicle")
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise

- Add `vehicle` and `time` to `load_lookup_dim`.

  curr.execute("SELECT vehicle_id, vehicle_key FROM dim_vehicle")         
  lookup["vehicle"] = {r[0]:r[1] for r in curr.fetchall()}

  curr.execute("SELECT time_key FROM dim_time")                            
  lookup["time"] = {r[0]: True for r in curr.fetchall()}



- In `transform`, resolve `vehicle_key` and `time_key` for each trip
  (remember `dim_time.time_key` is the requested time rounded **down** to
  the nearest 15-minute bucket, e.g. 14:37 → `1430`).

vehicle_key = None
if row["vehicle_id"] is not None:
    vehicle_key = lookups["vehicle"].get(row["vehicle_id"])
    if vehicle_key is None:
          logger.warning(f"trip {trip_id}: vehicle_id {row['vehicle_id']} not in dim_vehicle — skipped")
          skipped += 1
          continue



requested_at = row["requested_at"]
minute_bucket = (requested_at.minute // 15) * 15
time_key = (requested_at.hour * 100) + minute_bucket
if time_key not in lookups["time"]:
    logger.warning(f"trip {trip_id}: time_key {time_key} not in dim_time — skipped")
    skipped += 1
    continue               



- Wire the new columns through `load_fact_trips`.

INSERT INTO fact_trips
    (source_trip_id, date_key, driver_key, passenger_key, vehicle_key,      #new columns added vehicle_key, time_key, requested_at
     pickup_location_key, dropoff_location_key, time_key,
     payment_method_key, promo_code_key,
     base_fare, tip_amount, discount_amount, fare_amount,
     distance_km, duration_minutes,
     driver_rating, passenger_rating,
     surge_multiplier, requested_at)
    VALUES ( %(source_trip_id)s,
             %(date_key)s,
             %(driver_key)s,
             %(passenger_key)s,
             %(vehicle_key)s,                   #vehicle_key added
             %(pickup_location_key)s,
             %(dropoff_location_key)s,
             %(time_key)s,                      #time_key added
             %(payment_method_key)s,
             %(promo_code_key)s,
             %(base_fare)s,
             %(tip_amount)s,
             %(discount_amount)s,
             %(fare_amount)s,
             %(distance_km)s,
             %(duration_minutes)s,
             %(driver_rating)s,
             %(passenger_rating)s,
             %(surge_multiplier)s,
             %(requested_at)s
            )




## 3. Revenue by city / month

Write a warehouse query that returns total revenue grouped by pickup city
and month.

SELECT
    l.city_name AS pickup_city,
    d.year,
    d.month,
    SUM(f.fare_amount) AS total_revenue
FROM fact_trips f
JOIN dim_location l
    ON f.pickup_location_key = l.location_key
JOIN dim_date d
    ON f.date_key = d.date_key
GROUP BY
    l.city_name,
    d.year,
    d.month
ORDER BY
    l.city_name,
    d.year,
    d.month;



Then write the equivalent query against the OLTP schema (`trips`,
`locations`, etc.) directly.

SELECT
    l.city_name AS pickup_city,
    EXTRACT(YEAR FROM t.requested_at)::INT AS year,
    EXTRACT(MONTH FROM t.requested_at)::INT AS month,
    SUM(
        COALESCE(t.base_fare, 0) * COALESCE(t.surge_multiplier, 1)
        + COALESCE(t.tip_amount, 0)
        - COALESCE(t.discount_amount, 0)
    ) AS total_revenue
FROM trips t
JOIN locations l
    ON t.pickup_location_id = l.location_id
GROUP BY
    l.city_name,
    year,
    month
ORDER BY
    l.city_name,
    year,
    month;

**Answer:** how many table joins does each version need? Which one needed
fewer, and why?

Warehouse version needs 2 joins: 
fact_trips → dim_location and fact_trips → dim_date.
OLTP version needs 1 join: 
trips → locations.

The OLTP query needs fewer joins because it derives year/month directly 
from requested_at rather than joining through a separate dim_date table.





## 4. Payment method revenue

- Write a warehouse query for total revenue per payment method.

SELECT
    pm.name AS payment_method,
    SUM(f.fare_amount) AS total_revenue
FROM fact_trips f
JOIN dim_payment_method pm
    ON f.payment_method_key = pm.payment_method_key
GROUP BY
    pm.name
ORDER BY
    total_revenue DESC;


- Extend it (or write a second query) for **average fare per trip, per
  payment method, per month**.

  SELECT
    pm.name AS payment_method,
    d.year,
    d.month,
    COUNT(*) AS trip_count,
    AVG(f.fare_amount) AS avg_fare_per_trip
FROM fact_trips f
JOIN dim_payment_method pm
    ON f.payment_method_key = pm.payment_method_key
JOIN dim_date d
    ON f.date_key = d.date_key
GROUP BY
    pm.name,
    d.year,
    d.month
ORDER BY
    pm.name,
    d.year,
    d.month;

## 5. Busiest hour of day

Write a warehouse query that returns trip count per hour of day (0–23),
along with each hour's percentage of all trips — computed with a **window
function** (not a second query for the grand total).

SELECT
    t.hour,
    COUNT(*) AS trip_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_trips
FROM fact_trips f
JOIN dim_time t
    ON f.time_key = t.time_key
GROUP BY
    t.hour
ORDER BY
    t.hour;



## 7. Stretch: incremental load (watermark pattern)

Modify `etl.py` so the fact load only extracts trips newer than the
`MAX(requested_at)` already present in `fact_trips`. Where should that
watermark be read from, and what happens the very first time the ETL runs
against an empty warehouse?

def get_fact_watermark(conn):
    with conn.cursor() as curr:
        curr.execute("SELECT MAX(requested_at) AS max_requested_at FROM fact_trips")
        row = curr.fetchone()
        watermark = row[0] if row and row[0] is not None else None

    if watermark is None:
        logger.info("No fact_trips watermark found; extracting all source trips")
    else:
        logger.info(f"Using fact_trips watermark requested_at > {watermark}")

    return watermark


The watermark should be read from the destination warehouse:
SELECT MAX(requested_at) FROM fact_trips;


The very first time the ETL runs, fact_trips is empty. 
MAX(requested_at) returns NULL.
Here, ETL skips the watermark filter and loads all trips from the source database.