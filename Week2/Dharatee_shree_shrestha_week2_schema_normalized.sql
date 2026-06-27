-- week2_queries.sql
-- Week 2 Assignment
-- Submit file:
--    <your_name>week2_schema_normalized.sql  (your CREATE TABLE + INSERT migration)




---------- Table Creation----------


----Create table :locations

CREATE TABLE locations (
    location_id   SERIAL        PRIMARY KEY,
    city_name     VARCHAR(100)   NOT NULL UNIQUE
);


-- Create table: drivers
CREATE TABLE drivers (
    driver_id     SERIAL        PRIMARY KEY,
    name          VARCHAR(100)  NOT NULL
);



-- Create table: passenger
CREATE TABLE passengers (
    passenger_id     SERIAL        PRIMARY KEY,
    name          VARCHAR(100)  NOT NULL
);



-- Create table: payment_methods
CREATE TABLE payment_methods (
	payment_method_id SERIAL PRIMARY KEY,
	name VARCHAR(30) NOT NULL UNIQUE 
);


-- Create table: trips with Foreign Keys
CREATE TABLE trips (
    trip_id              SERIAL        PRIMARY KEY,
    driver_id            INTEGER       NOT NULL REFERENCES drivers(driver_id),
    passenger_id         INTEGER       NOT NULL REFERENCES passengers(passenger_id),
    pickup_location_id   INTEGER       NOT NULL REFERENCES locations(location_id),
    dropoff_location_id  INTEGER       NOT NULL REFERENCES locations(location_id),
    fare_amount          NUMERIC(10,2) NOT NULL CHECK (fare_amount > 0),
    distance_km          NUMERIC(6,2)  NOT NULL,
    status               varchar(50)   NOT NULL CHECK (status IN ('completed','cancelled','no_show')),
    requested_at         TIMESTAMP     NOT NULL,
    completed_at         TIMESTAMP,
    rating               NUMERIC(2,1)  CHECK (rating BETWEEN 1.0 AND 5.0),
    payment_method_id    INTEGER       REFERENCES payment_methods(payment_method_id)
);

SELECT * FROM drivers;


-- SELECT 
--     table_name
-- FROM 
--     information_schema.tables
-- WHERE 
--     table_schema = 'public';




---------- Data cleaning ----------



SELECT DISTINCT driver_name FROM rides r ;

SELECT DISTINCT trim(driver_name) FROM rides; --temporatily trim extra spaces

SELECT trim (' Sita  Tamang '); 



SELECT
	DISTINCT REPLACE(driver_name, '  ', '  ') --Sita Tamang with single space
FROM
	rides;



SELECT
	DISTINCT REPLACE(driver_name, '  ', '  ')  --Sita Tamang with double space
FROM
	rides;



SELECT
	DISTINCT lower(REPLACE(driver_name, '  ', ' '))  --lowercase driver names
FROM
	rides; 



SELECT
	DISTINCT upper(REPLACE(driver_name, '  ', ' '))  -- uppercase driver names
FROM
	rides; 



SELECT
	DISTINCT initcap(REPLACE(driver_name, '  ', ' '))  --initializes driver names
FROM
	rides; 



SELECT
	DISTINCT initcap(trim(regexp_replace(driver_name, '\s+', ' ', 'g'))) 
FROM
	rides;							--find one or more white spaces, replace with single white space; global (thoughout the string)


SELECT * FROM drivers;
	
	

---------- Data Insertion ----------

	

-- Insert cleaned data into drivers table	
INSERT INTO drivers (name)
SELECT
	DISTINCT INITCAP(TRIM(REGEXP_REPLACE(driver_name, '\s+', ' ', 'g')))
FROM
	rides;

SELECT * FROM drivers;



-- Insert cleaned data into passengers table
INSERT INTO passengers (name)
SELECT
	DISTINCT INITCAP(TRIM(REGEXP_REPLACE(rider_name, '\s+', ' ', 'g')))
FROM
	rides;

SELECT * FROM passengers;



--Insert combined pickup and dropoff location data into locations table
INSERT
	INTO
	locations(city_name)
SELECT
	DISTINCT(initcap(Trim(regexp_replace(pickup_city, '\s+', ' ', 'g'))))
FROM
	rides
UNION
SELECT
	DISTINCT(initcap(Trim(regexp_replace(dropoff_city, '\s+', ' ', 'g'))))
FROM
	rides;

SELECT * FROM locations;




-- Insert distinct payments, exclude null
INSERT
	INTO
	payment_methods(name) 
SELECT
	DISTINCT payment_method
FROM
	rides
WHERE
	payment_method IS NOT NULL;

SELECT * FROM payment_methods;


---reset the tables since duplicates formed
TRUNCATE TABLE
    trips,
    drivers,
    passengers,
    locations,
    payment_methods
RESTART IDENTITY;



---- Insert into trips table
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
SELECT 
(SELECT  driver_id 
	FROM drivers d 
	 WHERE d.name = INITCAP(TRIM(REGEXP_REPLACE(r.driver_name, '\s+', ' ', 'g')))) driver_id,
(SELECT  passenger_id 
		FROM passengers p
	 WHERE p.name = INITCAP(TRIM(REGEXP_REPLACE(r.passenger_name, '\s+', ' ', 'g')))) passenger_id,
(SELECT  location_id  
		FROM locations p
	 WHERE p.city_name = r.pickup_city ) pickup_location_id,
(SELECT  location_id  
		FROM locations p
	 WHERE p.city_name = r.dropoff_city ) dropoff_location_id,
fare_amount,
ride_distance_km,
ride_status,
requested_at,
completed_at,
rating,
(SELECT  payment_method_id  
		FROM payment_methods pm  
		WHERE pm.name = r.payment_method  ) payment_method_id
FROM rides r;

SELECT * FROM trips;
