# Big Data Lakehouse - Makefile for pipeline orchestration

.PHONY: help up down build dbt-deps dbt-seed dbt-run dbt-run-staging dbt-run-core dbt-run-marts dbt-run-snapshots dbt-test dbt-docs dbt-clean all rebuild

help:
	@echo "Available targets:"
	@echo "  up           - Start all Docker stacks (hadoop + pyspark)"
	@echo "  down         - Stop all Docker stacks"
	@echo "  build        - Build custom Docker images"
	@echo "  dbt-deps     - Install dbt packages"
	@echo "  dbt-run      - Run dbt models (staging -> core -> marts)"
	@echo "  dbt-test     - Run dbt tests"
	@echo "  dbt-docs     - Generate and serve dbt documentation"
	@echo "  dbt-clean    - Clean dbt target directory"
	@echo "  all          - Full pipeline: up -> build -> dbt-deps -> dbt-seed -> dbt-run -> dbt-test"

# Docker orchestration
up:
	docker network create bigdata 2>/dev/null || true
	cd hadoop && docker compose up -d
	@echo "Waiting for HDFS namenode to be healthy..."
	@until cd hadoop && docker compose exec -T namenode hdfs dfsadmin -report >/dev/null 2>&1; do \
		echo "  ...still waiting on HDFS"; sleep 3; \
	done
	cd hadoop && docker compose exec -T namenode hdfs namenode -format 2>/dev/null || true
	cd pyspark && docker compose up -d
	@echo "Waiting for Spark Thrift Server to accept connections..."
	@until cd pyspark && docker compose exec -T thriftserver bash -c "echo > /dev/tcp/localhost/10000" >/dev/null 2>&1; do \
		echo "  ...still waiting on Thrift Server"; sleep 3; \
	done

down:
	cd pyspark && docker compose down
	cd hadoop && docker compose down

build:
	cd pyspark && docker build -f Dockerfile.hive -t apache/hive:4.0.2 .
	cd pyspark && docker build -f Dockerfile.pyspark -t pyspark-notebook:1.3 .

# dbt commands (run inside dbt container)
dbt-deps:
	cd pyspark && docker compose run --rm dbt dbt deps

dbt-seed:
	cd pyspark && docker compose run --rm dbt dbt seed

dbt-run:
	cd pyspark && docker compose run --rm dbt dbt run

dbt-run-staging:
	cd pyspark && docker compose run --rm dbt dbt run --select staging

dbt-run-core:
	cd pyspark && docker compose run --rm dbt dbt run --select core

dbt-run-marts:
	cd pyspark && docker compose run --rm dbt dbt run --select marts

dbt-run-snapshots:
	cd pyspark && docker compose run --rm dbt dbt snapshot

dbt-test:
	cd pyspark && docker compose run --rm dbt dbt test

dbt-docs:
	cd pyspark && docker compose run --rm -p 8080:8080 dbt sh -c "dbt docs generate && dbt docs serve --port 8080 --host 0.0.0.0"

dbt-clean:
	cd pyspark && docker compose run --rm dbt dbt clean

# Full pipeline
all: up build dbt-deps dbt-seed dbt-run dbt-test

# Quick rebuild and test
rebuild: dbt-clean dbt-deps dbt-seed dbt-run dbt-test