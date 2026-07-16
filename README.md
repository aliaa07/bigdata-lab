# bigdata

A local big-data / lakehouse sandbox built with Docker: HDFS + YARN, Spark, Hive Metastore, and dbt, wired together to run a medallion-style (raw → bronze → silver → gold) data pipeline entirely on a laptop.

> **Status: work in progress.** The infrastructure is up and the early pipeline stages run in notebooks; dbt modeling and the gold layer are still being built out.

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

Implemented as PySpark notebooks under [`pyspark/jupyter/workspace`](pyspark/jupyter/workspace):

| Stage | Notebook | Purpose |
|---|---|---|
| Raw → Bronze | `raw to bronze.ipynb` | Ingest raw CSV into Delta tables, minimal transformation |
| Bronze → Silver | `bronze_to_sliver.ipynb` | Clean/conform bronze data |
| Silver → Gold | `silver_to_gold_tst.ipynb` | Business-level aggregates (in progress) |

dbt models (under [`pyspark/dbt-project`](pyspark/dbt-project)) will take over the silver/gold transformation layer, querying through Spark Thrift Server against the Hive-cataloged tables.

## Getting started

Prerequisites: Docker Desktop with WSL2 backend, an external `bigdata` network and the named volumes referenced in the compose files.

```bash
# create the network
docker network create bigdata

# storage + resource management
cd hadoop && docker compose up -d

# Note if this is the first time you are running this lab
# you need to format namenode after you ran the first docker compose up
docker compose run --rm -it namenode hdfs namenode -format


# compute + transformation
cd ../pyspark && \
    docker build -f Dockerfile.hive -t apache/hive:4.0.2 . && \
    docker build -f Dockerfile.pyspark -t pyspark-notebook:1.2 . && \
    docker compose up -d
```


| Service | URL |
|---|---|
| JupyterLab | http://localhost:8888 |
| HDFS NameNode UI | http://localhost:9870 |
| YARN ResourceManager UI | http://localhost:8088 |
| Spark History Server | http://localhost:18080 |
| Spark Thrift Server (JDBC) | `jdbc:hive2://localhost:10000/warehouse` |

## Roadmap

- [ ] Finish silver → gold aggregation logic
- [ ] Build out dbt models for the gold layer
- [ ] Replace example dbt project with real models
- [ ] Add a sample/seed dataset so the pipeline runs end-to-end out of the box
