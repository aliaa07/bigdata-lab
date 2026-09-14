# Local pipeline validation — 2026-09-14

Ran the project on Docker Desktop using the existing images. No Docker image
builds were performed. Changes are left uncommitted for review.

## Changes

- Reduced the local YARN deployment from four workers to two. Increased Thrift,
  Hive Metastore and dbt memory limits; Thrift's 1 GiB heap now has a 2 GiB container.
- Selected Spark 3.5's bundled Python bindings in Jupyter. Pinned PySpark/Delta
  Python versions in the Dockerfile for future builds; existing images were retained.
- Added bounded startup checks and noninteractive dbt commands. `make pipeline`
  runs dependencies, seed, snapshots, models, tests and docs sequentially.
  `make rebuild` starts services and runs that pipeline without building images.
  Fixed the documentation server command and the missing `make` in CI's marts step.
- Preserved fare cents, anchored arrivals to travel dates, and handled overnight
  times. Included travel date in the ticket fact key and removed invalid clustering columns.
- Joined current snapshot rows, retained snapshot history, made tie-breaking
  deterministic, and tested history keys separately from current business keys.
- Recalculated lifetime/daily totals across the available source so old corrections
  and late arrivals reach the models. Passenger segment keys no longer change with segment.
- Unified route keys and deduplicated flight operating measures across passenger
  tickets before daily aggregation. Conflicting operating measurements fail a test.
- Added SQL reconciliation checks and a live regression suite; updated both READMEs.

## Executed checks

- Fresh-volume `make ci-up`: guarded HDFS initialization and service startup succeeded.
- Initial main pipeline: loaded the 2,000-row seed, created three snapshots and
  five materialized models, and generated dbt documentation.
- `python hadoop/tests/test_startup.py`: all six startup safeguards passed.
- Live `python ../tests/test_pipeline.py` inside dbt: passed initial load,
  unchanged rerun, two passengers sharing a flight, exact cents, overnight duration,
  an old fare correction, a late flight, and changed loyalty attributes.
  Both full test invocations passed **74/74**, with zero warnings/errors/skips.
  Its unique temporary schema was removed afterward.
- `make dbt-clean`: removed generated artifacts and packages successfully.
- Subsequent `make rebuild` after cleanup: reinstalled packages, reseeded, merged
  all three snapshots and five materialized models, passed **74/74** main-warehouse
  tests with zero warnings/errors/skips, and regenerated the catalog. Exit code 0.
- `check_sample.py`: all nine tables retained identical row counts and content
  fingerprints after the complete rerun, excluding per-run metadata.
- `make dbt-docs`: succeeded; documentation, HDFS UI, YARN UI, Spark History UI
  and Jupyter all returned HTTP 200 on their published localhost ports.
- HDFS: one live DataNode; zero missing or corrupt blocks. YARN: two running
  workers and a running Spark Thrift application. Service health checks passed.
- `git diff --check`: passed.

The first run's cached dbt manifest omitted some generic tests after source edits.
A complete parse restored all 74; the final main rerun and live regression both
used the complete test suite. Generated documentation compiles tests but does
not execute them; the actual test results are recorded in the pipeline logs.

## Main warehouse row counts

| Relation | Rows |
| --- | ---: |
| sample_flight_data | 2,000 |
| dim_airport | 1,588 |
| dim_aircraft | 862 |
| dim_passenger | 2,000 |
| dim_route | 2,000 |
| fct_flight | 2,000 |
| fct_route_daily | 2,000 |
| fct_aircraft_daily | 1,993 |
| dim_passenger_segment | 2,000 |

## Reproduce

With existing images and initialized volumes:

```bash
make rebuild
docker compose -f pyspark/docker-compose.yaml exec -T dbt python ../tests/test_pipeline.py
make dbt-docs
```

For a content comparison across an unchanged rerun:

```bash
docker compose -f pyspark/docker-compose.yaml exec -T dbt python ../tests/check_sample.py --save logs/sample-before.json
make pipeline
docker compose -f pyspark/docker-compose.yaml exec -T dbt python ../tests/check_sample.py --compare logs/sample-before.json
```

`check_sample.py` compares counts and sorted content fingerprints for all nine
relations, excluding `source_uuid` and `dbt_updated_at`, which intentionally change
on fact/segment runs. Command transcripts are under
`pyspark/dbt-project/flight_data/logs/validation/`, especially `pipeline-rerun.log`,
`regression-run.log`, `sample-after-run.log`, and `docs-server-run.log`.
Before/after fingerprints are `logs/sample-before.json` and `logs/sample-after.json`.
Current catalog/manifest outputs are under `target/`.

## Boundaries

This validates the complete Make/dbt sample pipeline on the local Docker/YARN
stack. The separate historical notebooks are not executed by that pipeline.
Hosted GitHub Actions and future image builds were not run. Existing images may
still have the newer Python Delta SDK; the validated SQL path uses Delta 3.2 JVM
libraries. Source deletions/business-key changes require a model full refresh.
Elapsed times assume a shared clock and flights shorter than 24 hours because
the data has no time-zone offsets or arrival dates. Snapshot history records
observation time, and facts use current dimension attributes.
