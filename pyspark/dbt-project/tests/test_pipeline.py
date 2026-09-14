"""Run against the live stack: docker compose exec -T dbt python ../tests/test_pipeline.py.

Uses a unique, disposable schema. Exercises real dbt/Delta materializations,
including reruns, history, late arrivals and corrections, without changing warehouse.
Requires the main seed and dbt packages to be present.
"""
import os
import subprocess
import uuid
from decimal import Decimal

from pyhive import hive


schema = "regression_" + uuid.uuid4().hex[:12]
connection = hive.Connection(host="spark-thrift", port=10000, username="jovyan")
cursor = connection.cursor()


def sql(statement):
    cursor.execute(statement)
    # Spark Thrift advertises an empty result for some DDL statements that
    # PyHive cannot fetch. Only read rows from SELECT statements here.
    return cursor.fetchall() if statement.lstrip().lower().startswith("select") else []


def dbt(command):
    subprocess.run(
        ["dbt", command, "--target-path", "target/regression", "--log-path", "logs/regression"],
        env=dict(os.environ, DBT_SCHEMA=schema), check=True, timeout=1200,
    )


def check(statement, expected):
    actual = sql(statement)
    assert actual == expected, (statement, actual, expected)


def insert(flight, date, ticket, passenger, fare, flight_class="economy"):
    overrides = {
        "flight_id": repr(flight), "travel_date": f"date('{date}')",
        "itinerary_no": "1", "ticket_no": repr(ticket),
        "aircraft_id": "'regression-aircraft'", "airplane_model": "'Test plane'",
        "origin_airport": "'REG_ORIGIN'", "destination_airport": "'REG_DESTINATION'",
        "passenger_name": repr(passenger), "passenger_country": "'Test country'",
        "passenger_dob": "date('1990-01-01')", "frequent_flier": "false",
        "frequent_flier_no": "'REG_LOYALTY'", "flight_cost": str(fare),
        "departure_time": "'23:00:00'", "arrival_time": "'01:00:00'",
        "distance": "1000", "fuel_consumed_litre": "500",
        "passenger_flight_class": repr(flight_class),
    }
    # Other operational fields come from the same source row for every ticket.
    projection = ", ".join(overrides.get(c, f"`{c}`") for c in columns)
    sql(f"insert into {schema}.sample_flight_data select {projection} "
        "from (select * from warehouse.sample_flight_data order by flight_id, ticket_no limit 1) base")


try:
    print(f"Regression schema: {schema}", flush=True)
    sql(f"create database {schema}")
    sql(f"create table {schema}.sample_flight_data using delta as "
        "select * from warehouse.sample_flight_data where false")
    sql("select * from warehouse.sample_flight_data limit 0")
    columns = [c[0] for c in cursor.description]
    insert("flight-a", "2024-02-01", "ticket-a", "Passenger A", "100.25")
    insert("flight-a", "2024-02-01", "ticket-b", "Passenger B", "50.75", "business")
    insert("flight-b", "2024-03-01", "ticket-c", "Passenger A", "200.50")
    dbt("snapshot")
    dbt("run")
    check(f"select count(*), sum(revenue), min(flight_duration_mins), max(flight_duration_mins) "
          f"from {schema}.fct_flight", [(3, Decimal("351.50"), 120.0, 120.0)])
    check(f"select sum(flight_count), sum(total_distance_km), sum(total_fuel_litres), "
          f"sum(total_revenue), sum(premium_flights) from {schema}.fct_aircraft_daily",
          [(2, 2000, 1000.0, Decimal("351.50"), 1)])
    check(f"select sum(flight_count), sum(total_distance_km), sum(total_fuel_consumption), "
          f"sum(total_revenue), sum(business_class_flights) from {schema}.fct_route_daily",
          [(2, 2000, 1000.0, Decimal("351.50"), 1)])
    dbt("test")

    # Unchanged sources must preserve lifetime totals and snapshot row counts.
    dbt("snapshot")
    dbt("run")
    check(f"select count(*) from {schema}.dim_passenger", [(2,)])
    check(f"select total_flights, total_spend, segment from {schema}.dim_passenger_segment "
          "order by total_flights desc", [(2, Decimal("300.75"), "regular"),
                                           (1, Decimal("50.75"), "occasional")])

    sql(f"update {schema}.sample_flight_data set flight_cost=110.25 where ticket_no='ticket-a'")
    sql(f"update {schema}.sample_flight_data set frequent_flier=true where passenger_name='Passenger A'")
    insert("flight-late", "2024-01-01", "ticket-late", "Passenger A", "10.25")
    dbt("snapshot")
    dbt("run")
    check(f"select count(*), sum(revenue) from {schema}.fct_flight", [(4, Decimal("371.75"))])
    check(f"select count(*) from {schema}.dim_passenger", [(3,)])
    check(f"select count(*) from {schema}.dim_passenger where dbt_valid_to is null", [(2,)])
    check(f"select total_flights, total_spend, segment from {schema}.dim_passenger_segment "
          "order by total_flights desc", [(3, Decimal("321.00"), "regular"),
                                           (1, Decimal("50.75"), "occasional")])
    dbt("test")
    print("PASS: initial load, unchanged rerun, cents, overnight duration, shared-flight metrics, "
          "late arrival, old fare correction, snapshot history and lifetime totals", flush=True)
finally:
    # Only the unique schema created by this process can be removed.
    sql(f"drop database if exists {schema} cascade")
    cursor.close()
    connection.close()
