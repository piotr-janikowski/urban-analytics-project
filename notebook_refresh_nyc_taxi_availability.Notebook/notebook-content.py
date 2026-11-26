# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "c08039f2-25eb-4d23-a8ff-b81ef50a55bb",
# META       "default_lakehouse_name": "lakehouse_urban_analytics",
# META       "default_lakehouse_workspace_id": "c14a1c5d-5b0f-4b1a-af7d-bcb009b8c85f",
# META       "known_lakehouses": [
# META         {
# META           "id": "c08039f2-25eb-4d23-a8ff-b81ef50a55bb"
# META         }
# META       ]
# META     }
# META   }
# META }

# CELL ********************

spark.sql("DESCRIBE TABLE dbo.cfg_nyc_taxi_types").show(truncate=False)

#spark.sql("""
#    ALTER TABLE dbo.cfg_nyc_taxi_types
#    ADD COLUMNS (
#        max_year INT,
#        max_month INT,
#        max_date_key INT,
#        data_checked_at TIMESTAMP
#    )
#""")


# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import requests
from datetime import date

taxi_types = ["yellow", "green", "fhv", "fhvhv"]
base_url = "https://d37ci6vzurychx.cloudfront.net/trip-data/{taxi_type}_tripdata_{year}-{month:02d}.parquet"

def file_exists(taxi_type, year, month):
    url = base_url.format(taxi_type=taxi_type, year=year, month=month)
    response = requests.head(url, timeout=30, allow_redirects=True)
    return response.status_code == 200

def find_latest_available(taxi_type, min_year):
    today = date.today()
    year = today.year
    month = today.month

    while year >= min_year:
        if file_exists(taxi_type, year, month):
            return year, month
        month -= 1
        if month == 0:
            month = 12
            year -= 1

    return None

min_year = 2009
for taxi_type in taxi_types:
    result = find_latest_available(taxi_type, min_year)

    if result is None:
        print(taxi_type, "- lack of data")
        continue

    max_year, max_month = result
    max_date_key = max_year * 100 + max_month

    
    spark.sql(f"""
        UPDATE dbo.cfg_nyc_taxi_types
        SET max_year = {max_year},
            max_month = {max_month},
            max_date_key = {max_date_key},
            data_checked_at = current_timestamp()
        WHERE taxi_type = '{taxi_type}'
    """)

    print(taxi_type, "- latest data:", max_year, "-", max_month)



# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
