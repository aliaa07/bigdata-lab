# Flight Data Lakehouse

A local analytics lab built with Docker Compose, HDFS, YARN, Spark, Delta Lake, Hive Metastore, PostgreSQL, JupyterLab, and dbt. It explores flight, route, aircraft, and passenger analytics.

**Status:** infrastructure, notebooks, models, snapshots, tests, and a CI workflow are implemented. The September 2026 review found startup and data correctness issues that remain open. See [PROJECT_REVIEW.md](PROJECT_REVIEW.md) before treating the metrics as reliable or the project as complete. End-to-end release validation is still required.

## Architecture and data flow

Two Compose stacks communicate over the external Docker network `bigdata`:

| Stack | Services | Responsibility |
| --- | --- | --- |
| [Hadoop](hadoop/docker-compose.yaml) | NameNode, DataNode, ResourceManager, four NodeManagers, ownership initialization jobs | HDFS storage and YARN scheduling |
| [Analytics](pyspark/docker-compose.yaml) | JupyterLab, Spark History Server, Spark Thrift Server, Hive Metastore, PostgreSQL, dbt, HDFS initialization | Interactive processing, SQL execution, catalog, transformations |

Spark drivers run in JupyterLab or the Thrift Server container; executors run on YARN. PostgreSQL stores Hive catalog metadata. Delta files and Spark event logs live in HDFS.

The repository currently has **two separate data paths**. dbt reads the seed, not the notebook-produced silver table.

```text
Notebook path:
HDFS raw CSV -> 1_ingest_raw_data.ipynb -> warehouse.flight_raw (bronze)
  -> 2_bronze_to_sliver.ipynb -> warehouse.flight (silver)

dbt sample path:
sample_flight_data.csv -> dbt seed -> warehouse.sample_flight_data
  -> init_flight -> stage_flight -> stg_flight (ephemeral SQL)
       -> dim_airport / dim_aircraft / dim_passenger snapshots
       -> dim_route / fct_flight
            -> fct_route_daily / fct_aircraft_daily / dim_passenger_segment
```

The three snapshots also feed `fct_flight`; passenger attributes feed `dim_passenger_segment`. Models and snapshots use the `warehouse` schema.

## Prerequisites

- Docker Engine with Linux containers and the Docker Compose plugin. On Windows, use Docker Desktop with its WSL2 backend.
- Bash and GNU Make for Makefile recipes and the Bash examples below. Use WSL or another suitable Bash environment; several recipes do not work in native PowerShell or `cmd.exe`.
- Internet access for initial image builds, Python packages, Maven artifacts, and `dbt deps`.
- Available ports listed under [Service access](#service-access).

The current configuration starts four NodeManagers with 3 GiB container limits each. Combined service memory limits total approximately **17 GiB**, excluding Docker, the host OS, and other workloads. Limits are ceilings rather than guaranteed usage, but the comments about a 12 GiB WSL allocation do not establish that the full stack fits. Review sizing before startup: Spark Thrift requests a 1 GiB driver heap inside a 512 MiB container.

Dependencies run inside containers. The root `requirements.txt` is empty and is not a host installation procedure.

### Configured versions

| Component | Image or dependency |
| --- | --- |
| Hadoop | `apache/hadoop:3.5.0` |
| PySpark image | Local `pyspark-notebook:1.3`, built from `jupyter/pyspark-notebook:x86_64-ubuntu-22.04` |
| Delta JVM libraries | `delta-spark_2.12:3.2.0`, `delta-storage:3.2.0` |
| Hive image | Local tag `apache/hive:4.0.2`, built from `apache/hive:4.0.0` with PostgreSQL JDBC 42.7.4 |
| PostgreSQL | `postgres:17.5-bookworm` |
| dbt | `ghcr.io/dbt-labs/dbt-spark:1.9.latest` |

The PySpark Dockerfile uses an unpinned `pip install delta-spark`. The locally inspected image had Python PySpark 4.1.1 / Delta 4.2.0 alongside Spark 3.5.0 / Delta 3.2.0 JVM libraries. Resolve this mismatch before using notebooks or claiming reproducible builds. Delta 3.2.x supports Spark 3.5.x; see the [Delta compatibility matrix](https://docs.delta.io/releases/).

## Setup and startup

Run commands from the **repository root**. The following documents the intended manual workflow. Address the startup findings in [the review](PROJECT_REVIEW.md) before treating it as a verified clean-install guide.

### 1. Validate configuration and build

```bash
docker compose -f hadoop/docker-compose.yaml config --quiet
docker compose -f pyspark/docker-compose.yaml config --quiet
docker network inspect bigdata >/dev/null 2>&1 || docker network create bigdata
make build
```

Equivalent image build commands, also usable individually in PowerShell:

```bash
docker build -f pyspark/Dockerfile.hive -t apache/hive:4.0.2 pyspark
docker build -f pyspark/Dockerfile.pyspark -t pyspark-notebook:1.3 pyspark
```

### 2. Initialize a new HDFS installation

**Only for a new, empty installation with Hadoop stopped.** Existing installations must skip formatting and preserve their NameNode and DataNode volumes together. Never format a running NameNode or reformat an existing filesystem as a troubleshooting step.

Run the explicit initializer:

```bash
make init
```

`make init` refuses active, paused, or restarting NameNode/DataNode containers. The profile-only `namenode-format` service preserves storage when a NameNode `VERSION` file exists, formats only when both storage directories are empty, and refuses partial metadata or orphaned DataNode files. It runs after the ownership initializer and never uses forced formatting. If storage is rejected, recover it rather than deleting files to bypass the guard.

### 3. Start storage, then analytics

```bash
docker compose -f hadoop/docker-compose.yaml up -d
docker compose -f hadoop/docker-compose.yaml ps
docker compose -f hadoop/docker-compose.yaml exec -T namenode hdfs dfsadmin -report
docker compose -f hadoop/docker-compose.yaml exec -T resourcemanager yarn node -list
```

Wait for healthy services, a live DataNode, and registered NodeManagers. Then:

```bash
docker compose -f pyspark/docker-compose.yaml up -d
docker compose -f pyspark/docker-compose.yaml ps
docker compose -f pyspark/docker-compose.yaml logs --tail=100 hdfs-init hive-metastore spark-thrift
```

The `hdfs-init` job creates `/user/jovyan/spark-history` and `/user/hive/warehouse`. Once Spark Thrift and dbt are ready:

```bash
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt debug
```

For subsequent startup, use `make up` (also available as `make normal-up`) or repeat step 3. Routine `up`, `all`, and `rebuild` targets never format storage. `make ci-up` explicitly runs guarded initialization before startup; GitHub Actions selects separate volume names for each run.

## Run the dbt sample pipeline

The committed dbt seed contains **2,000 rows and 25 columns**, dated 2024-05-13 through 2025-03-08. It has a header. The separate `data/sample_flight.csv` contains **1,001 headerless rows** for notebook ingestion; [data/flight_data_schema](data/flight_data_schema) gives the field order.

After startup, use the long-running dbt service:

```bash
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt deps
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt seed --select sample_flight_data
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt snapshot
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt run
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt test
```

Snapshots must exist before dependent models run. Staging models are ephemeral: they expand into dependent SQL and do not create tables. The container working directory is `/usr/app/dbt/flight_data`; the profile is mounted at `/root/.dbt/profiles.yml`.

The service entrypoint is `tail -f /dev/null`, so plain `docker compose run dbt dbt ...` does not invoke dbt. For a one-off command against an already running stack, override the entrypoint:

```bash
docker compose -f pyspark/docker-compose.yaml run --rm --no-deps --entrypoint dbt dbt debug
```

After source changes, run snapshots, models, and tests again. Current incremental logic has known errors around late data, snapshot history, and passenger totals; consult the review before relying on repeated runs. `dbt run --full-refresh` rebuilds incremental models and does not reset snapshot history.

### Model inventory

| Model | Materialization | Intended grain or purpose |
| --- | --- | --- |
| `init_flight`, `stage_flight`, `stg_flight` | Ephemeral | Cast, stage, derive flight fields |
| `dim_airport` | SCD2 snapshot | Airport identity/history |
| `dim_aircraft` | SCD2 snapshot | Aircraft identity/model history |
| `dim_passenger` | SCD2 snapshot | Passenger identity/loyalty history |
| `dim_route` | Incremental Delta merge | Origin/destination pair |
| `fct_flight` | Incremental Delta merge; travel-date partitions | Passenger flight/ticket record; key hashes flight ID, itinerary, ticket |
| `fct_route_daily` | Incremental Delta merge | Route/day aggregates |
| `fct_aircraft_daily` | Incremental Delta merge | Aircraft/day aggregates |
| `dim_passenger_segment` | Incremental Delta merge | Passenger spend, frequency, segment |

Route and aircraft marts include revenue, distance, fuel, speed, engine performance, and class measures. Passenger segments use these rules, evaluated in order:

| Segment | Condition |
| --- | --- |
| `vip` | At least 10 flights and 50,000 total spend |
| `frequent` | At least 5 flights and 10,000 total spend |
| `regular` | At least 2 flights |
| `occasional` | Remaining passengers |

Currency and some source units are undocumented. Spellings such as `turbulance` and `avg_flight_speed_kmps` are retained; confirm units before interpreting metrics.

## Notebook ingestion

Open JupyterLab and work in `/home/jovyan/workspace`. The host directory `pyspark/jupyter` is mounted at `/home/jovyan`; the root `data` directory is not automatically mounted.

Stage the headerless sample at the HDFS path the notebook expects:

```bash
docker compose -f hadoop/docker-compose.yaml cp data/sample_flight.csv namenode:/tmp/flight_data.csv
docker compose -f hadoop/docker-compose.yaml exec -T -e HADOOP_USER_NAME=jovyan namenode hdfs dfs -mkdir -p /user/jovyan/rawdata
docker compose -f hadoop/docker-compose.yaml exec -T -e HADOOP_USER_NAME=jovyan namenode hdfs dfs -put /tmp/flight_data.csv /user/jovyan/rawdata/flight_data.csv
```

The upload fails if the destination already exists. A full `data/flight_data.csv` is not included. Your own headerless CSV must match the same 25-column order.

1. `1_ingest_raw_data.ipynb` writes `warehouse.flight_raw` at `/user/jovyan/lakehouse/bronze/flight`.
2. `2_bronze_to_sliver.ipynb` casts bronze fields and appends `warehouse.flight` at `/user/jovyan/lakehouse/silver/stage_flight`.

These notebooks need repairs for reliable Run All and reruns: ingestion has a partition-count error and unfinished diagnostic cells, and silver appends the full input again on each execution. dbt still reads the seed, so notebook execution does not change its input.

`Flight_dim.ipynb` and `silver_to_gold_tst.ipynb` are historical experiments. `Flight_dim.ipynb` drops or overwrites tables also used by dbt snapshots; run experiments in a separate schema. The older gold notebook also has outdated imports and storage paths.

## Service access

| Service | Host endpoint |
| --- | --- |
| JupyterLab | <http://localhost:8888> |
| HDFS NameNode UI | <http://localhost:9870> |
| YARN ResourceManager UI | <http://localhost:8088> |
| Spark History Server | <http://localhost:18080> |
| Notebook Spark UIs | Ports 4040–4045 while corresponding applications run |
| Spark Thrift application UI | <http://localhost:4046> while the application runs |
| Spark Thrift JDBC | `jdbc:hive2://localhost:10000/warehouse` |
| Hive Metastore | `thrift://localhost:9083` (not a browser UI) |
| dbt documentation | <http://localhost:8080> after starting the docs server |

Retrieve the Jupyter login URL/token from startup logs:

```bash
docker compose -f pyspark/docker-compose.yaml logs --tail=100 pyspark-notebook
```

Generate and serve dbt documentation in the foreground; stop the server with Ctrl+C:

```bash
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt docs generate
docker compose -f pyspark/docker-compose.yaml exec -T dbt dbt docs serve --port 8080 --host 0.0.0.0
```

The `make dbt-docs` readiness loop has a Compose working-directory error; use the explicit commands above until it is repaired.

This is a local lab configuration: PostgreSQL uses development credentials `hive` / `hive`, Hadoop proxy-user access is broad, and published ports are not restricted to loopback. Review exposure and authentication before making the services accessible outside a trusted development machine.

## Makefile and CI

`make help` lists targets. Against an initialized, healthy stack, these shortcuts are available:

```bash
make dbt-deps
make dbt-seed
make dbt-run-snapshots
make dbt-run
make dbt-test
make dbt-docs-generate
make down
```

Current limitations:

- `make init` initializes empty storage; `make up` / `make normal-up` create the network if needed and start an already initialized installation. Readiness loops still have no timeout.
- `make all` assumes HDFS has already been initialized. `make rebuild` still omits snapshots. Neither is a verified full pipeline while the remaining review findings are open.
- Pipeline steps are prerequisites, not a serial dependency chain; do not use `make -j` for them.
- `make dbt-clean` removes `target` and `dbt_packages`, including generated docs and validation artifacts. Run `dbt deps` again afterward.

[GitHub Actions](.github/workflows/main.yml) runs on pushes and pull requests to `main`. It checks startup safeguards, builds images, initializes isolated storage before starting services, runs dbt steps, generates docs, and tears down. Its marts step still invokes `dbt-run-marts` without `make`, and resource/dependency issues remain. Test logs and docs are not uploaded as artifacts.

## Validation and troubleshooting

[models/schema.yml](pyspark/dbt-project/flight_data/models/schema.yml) contains selected nullability, uniqueness, accepted class/segment values, positive distance/fuel-ratio checks, nonnegative revenue checks, and passenger relationships. `tests/` has no custom SQL tests. Model contracts are not enforced and dimension relationship coverage is incomplete.

The September 2026 review validated both Compose definitions, parsed Hadoop XML, Python utilities, and ordinary Python notebook cells, and ran isolated Spark 3.5 SELECT-level checks. Those checks exposed incorrect durations, rounded monetary amounts, unmatched route keys, and a repeat-run segmentation failure. They did **not** validate actual dbt materializations, Delta merges, a live YARN deployment, or the full CI pipeline. See [PROJECT_REVIEW.md](PROJECT_REVIEW.md) for evidence and proposed regression cases.

| Symptom | Check |
| --- | --- |
| `make: getcwd` or Compose path becomes `/hadoop/...` | Reset the WSL working directory with `cd /`, then run `make -C /mnt/c/Users/asus/Docker/bigdata up` for this checkout; use your own absolute checkout path elsewhere |
| External network missing | Inspect or create `bigdata` |
| NameNode failure or DataNode cluster ID mismatch | Inspect logs and volume history; do not reformat existing data |
| Thrift restarts or is killed | Check logs and its 512 MiB limit versus the 1 GiB driver heap |
| Notebook import/JVM errors | Compare Python PySpark/Delta versions with the JVM libraries |
| dbt cannot connect | Check Thrift health, YARN nodes, and `dbt debug` |
| dbt tables missing | Run seed and snapshots in order; verify `warehouse` and the profile |
| No dbt project file found | Use `exec dbt dbt ...`; project directory is `/usr/app/dbt/flight_data` |
| Port unavailable | Check for other local stacks using the published ports |

Useful diagnostics:

```bash
docker compose -f hadoop/docker-compose.yaml logs --tail=100 namenode datanode1 resourcemanager nodemanager
docker compose -f pyspark/docker-compose.yaml logs --tail=100 spark-thrift hive-metastore postgres
docker compose -f hadoop/docker-compose.yaml exec -T namenode hdfs dfsadmin -report
docker compose -f hadoop/docker-compose.yaml exec -T resourcemanager yarn node -list
```

Startup regression checks (Python 3, Bash, GNU Make, and Docker CLI required):

```bash
python hadoop/tests/test_startup.py
docker run --rm --network none --hostname localhost --memory 1g --cpus 1 \
  -v "$PWD/hadoop:/review:ro" \
  -v "$PWD/hadoop/hadoop-conf:/opt/hadoop/etc/hadoop:ro" \
  --entrypoint bash apache/hadoop:3.5.0 /review/tests/test-init-namenode.sh
```

The Python suite mocks Docker operations and validates Compose configuration. The container suite performs a real format in disposable storage, verifies repeated initialization preserves metadata and sample files, and checks refusal cases. It mounts no existing project storage volumes and refuses pre-existing test storage directories.

## Shutdown and persistence

```bash
docker compose -f pyspark/docker-compose.yaml down
docker compose -f hadoop/docker-compose.yaml down
```

Normal shutdown retains the named volumes:

| Volume | Contents |
| --- | --- |
| `bigdata_namenode_storage` | HDFS namespace and metadata |
| `bigdata_datanode1_storage` | HDFS blocks, including Delta files and event logs |
| `bigdata_metastore_db` | PostgreSQL Hive catalog |

Preserve these together for recovery. `BIGDATA_VOLUME_PREFIX` changes all three volume names; the default `bigdata` preserves existing development volumes. CI sets it to `bigdata-ci-<run-id>-<attempt>`. Keep the same prefix for initialization, startup, and shutdown. This isolates storage names, not service ports or container names; it is not a configuration for concurrent local clusters.

Notebooks, dbt source, installed dbt packages, and generated dbt outputs are host bind mounts. Volume removal and NameNode formatting are destructive resets, not normal shutdown.

## Repository layout

```text
.
├── .github/workflows/main.yml
├── data/                          # Headerless sample and field order
├── hadoop/
│   ├── docker-compose.yaml
│   ├── hadoop-conf/                # HDFS, YARN, Hive client configuration
│   ├── scripts/init-namenode.sh    # Guarded, explicit first initialization
│   └── tests/                     # Storage and orchestration regression checks
├── models/                        # Placeholder, not the dbt model directory
├── pyspark/
│   ├── Dockerfile.hive
│   ├── Dockerfile.pyspark
│   ├── docker-compose.yaml
│   ├── spark-conf/
│   ├── jupyter/workspace/          # Notebooks and Utils/
│   ├── dbt-profiles/profiles.yml
│   └── dbt-project/flight_data/
│       ├── dbt_project.yml
│       ├── packages.yml
│       ├── package-lock.yml
│       ├── models/                # staging/, core/, marts/, schema.yml, sources.yml
│       ├── snapshots/
│       ├── seeds/
│       ├── macros/
│       ├── analyses/
│       └── tests/
├── Makefile
├── PROJECT_REVIEW.md
└── README.md
```

## Remaining wrap-up work

Complete the prioritized modifications in [PROJECT_REVIEW.md](PROJECT_REVIEW.md), then validate a clean install and a second pipeline run, retain results, and update this status. Dataset provenance, currency/units, and a repository license remain undocumented.
