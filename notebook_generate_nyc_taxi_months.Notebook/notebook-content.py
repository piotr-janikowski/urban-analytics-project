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

# Parameters
taxi_config_json = taxi_config_json = '[{"taxi_type":"yellow","min_date_key":200901,"max_date_key":202609},{"taxi_type":"green","min_date_key":201308,"max_date_key":202609}]'
requested_start_key = 201501
requested_end_key = 201501

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import json
import time
import requests

from concurrent.futures import ThreadPoolExecutor


configs = json.loads(taxi_config_json)

requested_start_key = int(requested_start_key)
requested_end_key = int(requested_end_key)

if not configs:
    raise ValueError("No taxi configurations received.")

if requested_start_key > requested_end_key:
    raise ValueError("Start date cannot be later than end date.")


def to_index(date_key):
    year, month = divmod(int(date_key), 100)

    if not 1 <= month <= 12:
        raise ValueError(f"Invalid date key: {date_key}")

    return year * 12 + month - 1


def to_date_key(index):
    year, month = divmod(index, 12)
    return year * 100 + month + 1


start_index = to_index(requested_start_key)
end_index = to_index(requested_end_key)

tasks = []
effective_ranges = []
outside_source_ranges = []
no_overlap = []

for config in configs:
    taxi_type = config["taxi_type"]
    min_key = int(config["min_date_key"])
    max_key = int(config["max_date_key"])

    min_index = to_index(min_key)
    max_index = to_index(max_key)

    effective_start = max(start_index, min_index)
    effective_end = min(end_index, max_index)

    if start_index < min_index:
        outside_source_ranges.append({
            "taxi_type": taxi_type,
            "from_key": requested_start_key,
            "to_key": to_date_key(min(min_index - 1, end_index))
        })

    if end_index > max_index:
        outside_source_ranges.append({
            "taxi_type": taxi_type,
            "from_key": to_date_key(max(max_index + 1, start_index)),
            "to_key": requested_end_key
        })

    if effective_start > effective_end:
        no_overlap.append(taxi_type)
        continue

    effective_ranges.append({
        "taxi_type": taxi_type,
        "start_key": to_date_key(effective_start),
        "end_key": to_date_key(effective_end)
    })

    tasks.extend(
        (taxi_type, index)
        for index in range(effective_start, effective_end + 1)
    )


base_url = ("https://d37ci6vzurychx.cloudfront.net/trip-data/{taxi_type}_tripdata_{year}-{month:02d}.parquet")


def check_month(task):
    taxi_type, index = task

    year, month = divmod(index, 12)
    month += 1

    url = base_url.format(taxi_type=taxi_type, year=year, month=month)

    record = {
        "taxi_type": taxi_type,
        "year": year,
        "month": f"{month:02d}",
        "date_key": year * 100 + month,
        "file_name": f"{taxi_type}_tripdata_{year}-{month:02d}.parquet",
        "file_url": url
    }

    for attempt in range(3):
        try:
            response = requests.head(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=(5, 20), allow_redirects=True)

            if response.status_code == 200:
                return {**record, "status": "available"}

            if response.status_code == 404:
                return {**record, "status": "missing"}

            if response.status_code in (429, 500, 502, 503, 504):
                if attempt < 2:
                    time.sleep(2 ** attempt)
                    continue

            return {
                **record,
                "status": "failed",
                "http_status": response.status_code
            }

        except requests.RequestException as error:
            if attempt < 2:
                time.sleep(2 ** attempt)
                continue

            return {
                **record,
                "status": "failed",
                "error": str(error)
            }


with ThreadPoolExecutor(max_workers=5) as executor:
    results = list(executor.map(check_month, tasks))


available = [r for r in results if r["status"] == "available"]
missing = [r for r in results if r["status"] == "missing"]
failed = [r for r in results if r["status"] == "failed"]

result = {
    "effective_ranges": effective_ranges,
    "outside_source_ranges": outside_source_ranges,
    "no_overlap": no_overlap,
    "available": available,
    "missing": missing,
    "failed": failed,
    "summary": {
        "checked_months": len(results),
        "available_count": len(available),
        "missing_count": len(missing),
        "failed_count": len(failed)
    }
}

result_json = json.dumps(result, separators=(",", ":"))

print(json.dumps(result["summary"], indent=2))
print("Effective ranges:", effective_ranges)
print("Outside source ranges:", outside_source_ranges)
print("No overlap:", no_overlap)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

notebookutils.notebook.exit(result_json)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
