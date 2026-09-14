# flight_data dbt project

Spark SQL models for flight, route, aircraft and passenger analytics, using Delta Lake and Spark Thrift. The active profile is `flight_data`, target `dev`, schema `warehouse`.

See the [repository README](../../../README.md) for a setup, service access, resource planning, and persistence. Review [the open findings](../../../PROJECT_REVIEW.md) before relying on metrics or incremental runs.

## Input and dependency order

The active input is `warehouse.sample_flight_data`, loaded from the committed 2,000-row seed. The notebook-produced `warehouse.flight` table is not connected to the dbt source.

```text
sample_flight_data -> init_flight -> stage_flight -> stg_flight
  -> dim_airport, dim_aircraft, dim_passenger snapshots
  -> dim_route, fct_flight
       -> fct_route_daily, fct_aircraft_daily, dim_passenger_segment
```

`fct_flight` also joins all three snapshots. Staging is ephemeral; core/mart models use incremental Delta merges. `fct_flight` is partitioned by `travel_date`.

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
- `tests/`: placeholder; no custom SQL regression tests.

Current tests cover selected nullability, uniqueness, accepted values, numeric checks, and passenger relationships. They do not establish correct snapshot history, lifetime segmentation, late-data handling, or flight-level aggregation. Those issues, timestamp/currency casts, and route keys are documented in [PROJECT_REVIEW.md](../../../PROJECT_REVIEW.md).
