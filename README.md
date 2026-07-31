# bigdata

A local big-data / lakehouse sandbox built with Docker: HDFS + YARN, Spark, Hive Metastore, and dbt, wired together to run a medallion-style (raw → bronze → silver → gold) data pipeline entirely on a laptop.

> **Status: dbt modeling complete.** Infrastructure is up, bronze→silver runs in notebooks, silver→gold is implemented in dbt with tests and documentation.

## Architecture

Two Docker Compose stacks share an external `bigdata` network:

**[`hadoop/`](hadoop/docker-compose.yaml) — storage & resource management**
- HDFS NameNode + DataNode
- YARN ResourceManager + NodeManager (scalable replica)

**[`pyspark/`](pyspark/docker-compose.yaml) — compute & transformation**
- JupyterLab notebook server running PySpark (submits jobs to YARN)
- Spark History Server
- Hive Metastore (Postgres-backed) — table catalog for the data lake
- Spark Thrift Server — JDBC/HiveServer2-compatible endpoint
- dbt-core + dbt-spark, connecting to Spark Thrift for SQL-based modeling

Both stacks are tuned with laptop-sized resource limits (commented-out production-scale equivalents are left alongside each, see the compose files).

## Pipeline

### Medallion Layers

| Stage | Implementation | Purpose |
|-------|----------------|---------|
| Raw → Bronze | `pyspark/jupyter/workspace/1_ingest_raw_data.ipynb` | Ingest raw CSV into Delta tables, minimal transformation |
| Bronze → Silver | `pyspark/jupyter/workspace/2_bronze_to_sliver.ipynb` | Clean/conform bronze data → typed Delta table `warehouse.flight` |
| Silver → Gold | **dbt models** (see below) | Business-level aggregates via dbt on Spark Thrift |

### dbt Models (Source of Truth)

```
models/
├── staging/
│   └── stg_flight.sql          # ephemeral — cleans & types raw flight data
├── core/
│   ├── dim_route.sql           # incremental — origin/destination pairs
│   └── fct_flight.sql          # incremental — fact table, grain: flight+passenger
├── marts/
│   ├── fct_route_daily.sql     # incremental — daily route aggregates
│   ├── fct_aircraft_daily.sql  # incremental — daily aircraft utilization
│   └── dim_passenger_segment.sql # incremental — passenger segmentation
snapshots/
├── dim_airport.sql             # SCD2 — airport dimension
├── dim_aircraft.sql            # SCD2 — aircraft attributes
└── dim_passenger.sql           # SCD2 — passenger profile
```

**Materializations**: ephemeral for staging, incremental (merge) for core/marts, snapshots for SCD2 dims.

### Business Metrics (Gold Layer)

- **Route Daily**: flights, revenue, distance, fuel, speed, turbulence, class mix per route/day
- **Aircraft Daily**: utilization, revenue/km, fuel efficiency, engine performance per aircraft/day
- **Passenger Segments**: VIP / frequent / regular / occasional by spend & frequency + age groups

## Getting Started

Prerequisites: Docker Desktop with WSL2 backend.

```bash
# create the network
docker network create bigdata

# storage + resource management
cd hadoop && docker compose up -d

# Note: first run only — format namenode
docker compose run --rm -it namenode hdfs namenode -format

# compute + transformation
cd ../pyspark && \
    docker build -f Dockerfile.hive -t apache/hive:4.0.2 . && \
    docker build -f Dockerfile.pyspark -t pyspark-notebook:1.3 . && \
    docker compose up -d
```

Or use the Makefile for one-command orchestration:

```bash
make all        # full pipeline: up → build → dbt-deps → dbt-seed → dbt-run → dbt-test
make dbt-run    # run dbt models only
make dbt-test   # run dbt tests only
make dbt-docs   # generate & serve dbt docs on http://localhost:8080
```

### Service URLs

| Service | URL |
|---|---|
| JupyterLab | http://localhost:8888 |
| HDFS NameNode UI | http://localhost:9870 |
| YARN ResourceManager UI | http://localhost:8088 |
| Spark History Server | http://localhost:18080 |
| Spark Thrift Server (JDBC) | `jdbc:hive2://localhost:10000/warehouse` |
| dbt Docs | http://localhost:8080 (after `make dbt-docs`) |

## Development

### Run notebooks (prototype only)
1. Open JupyterLab at http://localhost:8888
2. Run `1_ingest_raw_data.ipynb` → `2_bronze_to_sliver.ipynb`
3. Data lands in `warehouse.flight` (Delta on HDFS)

### dbt workflow (production logic)
```bash
# inside pyspark dir, or use Makefile
cd pyspark
docker compose run --rm dbt dbt deps      # install packages
docker compose run --rm dbt dbt seed      # load sample data
docker compose run --rm dbt dbt run       # build all models
docker compose run --rm dbt dbt test      # run tests
docker compose run --rm dbt dbt snapshot  # update SCD2 dims
```

### Project Structure
```
.
├── hadoop/                    # HDFS + YARN stack
│   ├── docker-compose.yaml
│   └── hadoop-conf/
├── pyspark/                   # Spark + Hive + dbt stack
│   ├── docker-compose.yaml
│   ├── Dockerfile.hive
│   ├── Dockerfile.pyspark
│   ├── spark-conf/
│   ├── jupyter/workspace/     # prototype notebooks
│   ├── dbt-profiles/          # profiles.yml (mounted to /root/.dbt)
│   └── dbt-project/
│       └── flight_data/       # dbt project
│           ├── models/
│           │   ├── staging/
│           │   ├── core/
│           │   └── marts/
│           ├── snapshots/
│           ├── seeds/
│           ├── tests/
│           ├── macros/
│           ├── schema.yml     # model contracts + tests
│           ├── dbt_project.yml
│           └── packages.yml
├── data/                      # raw CSV (flight_data.csv)
├── Makefile                   # pipeline orchestration
└── README.md
```

## Data Quality & Tests

- **Schema tests**: not_null, unique, accepted_values on all key columns
- **Referential integrity**: relationships between fact ↔ dims
- **Business rules**: revenue ≥ 0, distance > 0, valid flight classes
- **Uniqueness**: flight_id + travel_date + passenger_key in fct_flight

Run `make dbt-test` to execute all tests.

## Roadmap

- [x] Bronze → Silver notebook working
- [x] Silver → Gold dbt models (core + marts)
- [x] SCD2 snapshots for all dimensions
- [x] Sample seed data for reproducibility
- [x] dbt tests & documentation
- [x] Makefile for one-command pipeline
- [ ] CI/CD (GitHub Actions: lint, compile, test)
- [ ] Partition pruning optimization for large datasets
- [ ] Incremental prediction model (e.g., delay prediction)