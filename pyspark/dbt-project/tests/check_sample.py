"""Capture and compare the sample warehouse, excluding per-run fact metadata."""
import argparse
import json
from pathlib import Path

from pyhive import hive

parser = argparse.ArgumentParser()
parser.add_argument("--save", type=Path)
parser.add_argument("--compare", type=Path)
args = parser.parse_args()

tables = ["sample_flight_data", "dim_airport", "dim_aircraft", "dim_passenger",
          "dim_route", "fct_flight", "fct_route_daily", "fct_aircraft_daily", "dim_passenger_segment"]
connection = hive.Connection(host="spark-thrift", port=10000, username="jovyan")
cursor = connection.cursor()
result = {}
for table in tables:
    cursor.execute(f"select * from warehouse.{table} limit 0")
    columns = [f"`{c[0]}`" for c in cursor.description if c[0] not in ("source_uuid", "dbt_updated_at")]
    cursor.execute(f"select count(*), sha2(to_json(sort_array(collect_list("
                   f"to_json(struct({','.join(columns)}))))),256) from warehouse.{table}")
    count, digest = cursor.fetchone()
    result[table] = {"rows": count, "sha256": digest}
cursor.close()
connection.close()
assert result["sample_flight_data"]["rows"] == 2000, result
assert result["fct_flight"]["rows"] == 2000, result
if args.compare:
    previous = json.loads(args.compare.read_text())
    assert result == previous, {t: (previous.get(t), result[t]) for t in tables if previous.get(t) != result[t]}
    print("PASS: all nine tables have identical content after the pipeline rerun (excluding per-run fact metadata).")
if args.save:
    args.save.parent.mkdir(parents=True, exist_ok=True)
    args.save.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
