# flight_data dbt project

Spark SQL models for flight, route, aircraft and passenger analytics, using Delta Lake and Spark Thrift. The active profile is `flight_data`, target `dev`, schema `warehouse`.

See the [repository README](../../../README.md) for setup, service access, resource planning, and persistence. `make pipeline` runs the complete sample workflow using an already running stack; `make rebuild` starts the stack first and uses existing images.

## Input and dependency order

The active input is `warehouse.sample_flight_data`, loaded from the committed 2,000-row seed. The notebook-produced `warehouse.flight` table is not connected to the dbt source.

```text
sample_flight_data -> init_flight -> stage_flight -> stg_flight
  -> dim_airport, dim_aircraft, dim_passenger snapshots
  -> dim_route, fct_flight
       -> fct_route_daily, fct_aircraft_daily, dim_passenger_segment
```

`fct_flight` joins the current row from each snapshot using stable business keys. Staging and `int_flight_operation` are ephemeral; materialized core/mart models use Delta merges. `fct_flight` is partitioned by `travel_date` and keyed by flight/date/itinerary/ticket. Operational measures are reduced to one flight occurrence before daily aggregation; fares remain additive across tickets.

Without an ingestion timestamp, every run scans the full source and recalculates aggregates. This includes late arrivals and historical corrections. Source deletions and changes to business keys require a full model refresh. Snapshot dates record when attributes were observed; facts do not perform travel-time SCD lookups. Passenger segments contain one row per passenger, using lifetime totals and current attributes.

Fares retain two decimal places. Times use the travel date, adding a day when arrival time precedes departure time. The source lacks time-zone offsets and explicit arrival dates; durations assume a shared clock and flights shorter than 24 hours.

## Commands

From the **repository root**, after services are healthy:

```bash
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt deps
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt seed --select sample_flight_data
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt snapshot
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt run
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt test
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt docs generate
```

Append `--select core` or `--select marts` to `dbt run` to run a subset after its dependencies exist. A plain `dbt run` does not load seeds or execute snapshots. Use `exec` because the service entrypoint is `tail`; one-off containers require `--entrypoint dbt`.

Inside the container the working directory is `/usr/app/dbt/flight_data`; profiles are in `/root/.dbt`. Outputs and logs live in this project's `target/` and `logs/`. `dbt clean` removes `target/` and `dbt_packages/`; retain validation outputs first and rerun `dbt deps` afterward.

## Project contents

- `models/staging/`: source casts, intermediate projection, derived measures.
- `models/core/`: route dimension and passenger-flight fact.
- `models/marts/`: route/day and aircraft/day aggregates and passenger segments.
- `snapshots/`: airport, aircraft, and passenger dimensions using the `check` strategy and hard-delete invalidation.
- `models/schema.yml`: descriptions and generic tests.
- `models/sources.yml`: source configuration.
- `packages.yml` / `package-lock.yml`: package declarations and resolutions.
- `tests/`: source-to-fact fare/duration reconciliation, lifetime-total reconciliation, and consistent flight-operation checks.
- `../tests/test_pipeline.py`: live regression suite using a unique temporary schema.

Generic tests cover nullability, uniqueness, accepted values, numeric checks, and passenger/route relationships. Snapshot keys are unique among current rows, while `dbt_scd_id` is unique across history. Run the regression suite after the main pipeline:

```bash
docker compose -f pyspark/docker-compose.yaml exec -T dbt python ../tests/test_pipeline.py
```

It verifies real Delta writes and merges with repeated passengers, shared flights, overnight times, cents, unchanged reruns, an old fare correction, a late arrival, and changed loyalty attributes. It cleans up its own temporary schema. `DBT_SCHEMA` overrides the default `warehouse` schema for isolated runs.
