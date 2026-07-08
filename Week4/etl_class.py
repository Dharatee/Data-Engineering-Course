import psycopg2
import os
from dotenv import load_dotenv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

SRC_DB_CONFIG = {
    "host":    os.getenv("SRC_DB_HOST"),
    "port":     os.getenv("SRC_DB_PORT"),
    "dbname":   os.getenv("SRC_DB_NAME"),
    "user":     os.getenv("SRC_DB_USER"),
    "password": os.getenv("SRC_DB_PASSWORD"),
}

DEST_DB_CONFIG = {
    "host":    os.getenv("DEST_DB_HOST"),
    "port":     os.getenv("DEST_DB_PORT"),
    "dbname":   os.getenv("DEST_DB_NAME"),
    "user":     os.getenv("DEST_DB_USER"),
    "password": os.getenv("DEST_DB_PASSWORD"),
}

def load_dim_drivers(conn, driver_data):
    insert_dim_driver_sql = """
    INSERT INTO dim_drivers (
        driver_id,
        name,
        status,
        joined_at,
        tenure_bucket
    ) VALUES (
        %(driver_id)s,
        %(name)s,
        %(status)s,
        %(joined_at)s,
        %(tenure_bucket)s
    )
    ON CONFLICT (driver_id) DO NOTHING;
    """

    try:
        with conn.cursor() as cur:  
            cur.executemany(insert_dim_driver_sql, driver_data)
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(f"Error loading dim_drivers: {e}")
        raise



def main():
    src_conn = psycopg2.connect(**SRC_DB_CONFIG)
    dest_conn = psycopg2.connect(**DEST_DB_CONFIG)
    oltp_drivers = extract_driver(src_conn)
    #print(oltp_drivers[0])
    load_dim_drivers(dest_conn, oltp_drivers)

def extract_driver(conn):
    get_driver_sql = """
SELECT
    driver_id,
    name,
    status,
    joined_at,
    CASE
        WHEN joined_at >= NOW() - INTERVAL '6 months' THEN '0-6 months'
        WHEN joined_at >= NOW() - INTERVAL '1 year' THEN '6-12 months'
        WHEN joined_at >= NOW() - INTERVAL '2 years' THEN '1-2 years'
        ELSE '2+ years'
    END AS tenure_bucket
FROM
    drivers d;
"""
    with conn.cursor() as curr:
        curr.execute(get_driver_sql)
        rows = curr.fetchall()
    return rows

"""""
SELECT
        driver_id ,
        name,
        status ,
        joined_at,
        CASE
            WHEN joined_at >= NOW() - INTERVAL '6 months'  THEN '0-6 months'
            WHEN joined_at >= NOW() - INTERVAL '1 year'    THEN '6-12 months'
            WHEN joined_at >= NOW() - INTERVAL '2 years'   THEN '1-2 years'
        ELSE '2+ years'
        END  AS tenure_bucket
    FROM
        drivers d ;
"""


if __name__ == "__main__":
    main()