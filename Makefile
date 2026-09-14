# ============================================================
# Big Data Lakehouse - Makefile
# Pipeline orchestration
# ============================================================

.PHONY: help \
	network init up ci-up normal-up down build \
	dbt-deps dbt-seed \
	dbt-run dbt-run-staging dbt-run-core dbt-run-marts dbt-run-snapshots \
	dbt-test dbt-docs dbt-docs-generate dbt-clean \
	pipeline all rebuild

# ============================================================
# Project directories
# ============================================================

HADOOP_DIR  := $(CURDIR)/hadoop
PYSPARK_DIR := $(CURDIR)/pyspark

# ============================================================
# Help
# ============================================================

help:
	@echo "Available targets:"
	@echo ""
	@echo "Docker:"
	@echo "  build              - Build custom Docker images"
	@echo "  init               - Initialize empty HDFS storage (Hadoop must be stopped)"
	@echo "  up                 - Start Hadoop and PySpark"
	@echo "  down               - Stop all Docker stacks"
	@echo ""
	@echo "dbt:"
	@echo "  dbt-deps           - Install dbt packages"
	@echo "  dbt-seed           - Load dbt seeds"
	@echo "  dbt-run            - Run all dbt models"
	@echo "  dbt-run-staging    - Run staging models"
	@echo "  dbt-run-core       - Run core models"
	@echo "  dbt-run-marts      - Run marts models"
	@echo "  dbt-run-snapshots  - Run dbt snapshots"
	@echo "  dbt-test           - Run dbt tests"
	@echo "  dbt-docs-generate  - Generate dbt documentation"
	@echo "  dbt-docs           - Generate and serve dbt documentation"
	@echo "  dbt-clean          - Clean dbt target directory"
	@echo ""
	@echo "Pipeline:"
	@echo "  pipeline           - Run seed, snapshots, models, tests and docs (no image build)"
	@echo "  all                - Build images, start services, run pipeline"
	@echo "  rebuild            - Re-run pipeline using existing images"

# ============================================================
# Docker image build
# ============================================================
build:
	@echo "Building Hive image..."
	cd $(PYSPARK_DIR) && docker build \
		-f Dockerfile.hive \
		-t apache/hive:4.0.2 \
		.

	@echo "Building PySpark image..."
	cd $(PYSPARK_DIR) && docker build \
		-f Dockerfile.pyspark \
		-t pyspark-notebook:1.3 \
		.

# ============================================================
# Docker orchestration
# ============================================================

network:
	docker network inspect bigdata >/dev/null 2>&1 || docker network create bigdata

init: network
	@states=$$(docker compose -f "$(HADOOP_DIR)/docker-compose.yaml" ps --all --format '{{.State}}' namenode datanode1) || exit $$?; \
	for state in $$states; do \
		case "$$state" in \
			created|exited) ;; \
			*) echo "Stop the Hadoop stack before running make init (state: $$state)." >&2; exit 1 ;; \
		esac; \
	done
	docker compose -f "$(HADOOP_DIR)/docker-compose.yaml" run --rm namenode-format

# CI initializes its isolated volumes before starting any Hadoop daemons.
# Re-enter the absolute directory for each child make (WSL can lose its cwd).
ci-up:
	$(MAKE) -C "$(CURDIR)" init
	$(MAKE) -C "$(CURDIR)" up

normal-up: up

# Routine startup never formats storage. Run make init once on a new install.
up: network

	@echo "Starting Hadoop..."
	cd $(HADOOP_DIR) && docker compose up -d --wait --wait-timeout 300

	@echo "Waiting for HDFS NameNode to be healthy..."
	@attempt=0; until (cd $(HADOOP_DIR) && docker compose exec -T namenode hdfs dfsadmin -report >/dev/null 2>&1); do \
		attempt=$$((attempt + 1)); [ $$attempt -lt 60 ] || { echo "HDFS readiness timed out" >&2; exit 1; }; \
		echo "  ...still waiting on HDFS"; \
		sleep 3; \
	done

	@echo "Starting PySpark..."
	cd $(PYSPARK_DIR) && docker compose up -d --wait --wait-timeout 300

	@echo "Waiting for Spark Thrift Server to accept connections..."
	@attempt=0; until (cd $(PYSPARK_DIR) && docker compose exec -T spark-thrift bash -c "echo > /dev/tcp/localhost/10000" >/dev/null 2>&1); do \
		attempt=$$((attempt + 1)); [ $$attempt -lt 60 ] || { echo "Thrift readiness timed out" >&2; exit 1; }; \
		echo "  ...still waiting on Thrift Server"; \
		sleep 3; \
	done

	@echo "Big Data stack is ready."

down:
	@echo "Stopping PySpark..."
	cd $(PYSPARK_DIR) && docker compose down --remove-orphans

	@echo "Stopping Hadoop..."
	cd $(HADOOP_DIR) && docker compose down --remove-orphans

# ============================================================
# dbt commands
# ============================================================

dbt-deps:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt deps

dbt-seed:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt seed --select sample_flight_data

dbt-run:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt run

dbt-run-staging:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt run --select staging

dbt-run-core:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt run --select core

dbt-run-marts:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt run --select marts

dbt-run-snapshots:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt snapshot

dbt-test:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt test

dbt-docs-generate:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt docs generate

dbt-docs:
	$(MAKE) -C "$(CURDIR)" dbt-docs-generate
	cd $(PYSPARK_DIR) && docker compose exec -d dbt sh -c \
		"dbt docs serve --port 8080 --host 0.0.0.0 > /tmp/dbt-docs.log 2>&1"

	@echo "Waiting for dbt docs server..."
	@attempt=0; until (cd $(PYSPARK_DIR) && docker compose exec -T dbt python -c \
		"import urllib.request; urllib.request.urlopen('http://localhost:8080', timeout=2)" \
		>/dev/null 2>&1); do \
		attempt=$$((attempt + 1)); [ $$attempt -lt 60 ] || { echo "dbt docs readiness timed out" >&2; exit 1; }; \
		sleep 1; \
	done

	@echo "dbt docs server is ready on port 8080"

dbt-clean:
	cd $(PYSPARK_DIR) && docker compose exec -T dbt dbt clean

# ============================================================
# Full pipeline
# ============================================================

pipeline:
	$(MAKE) -C "$(CURDIR)" dbt-deps
	$(MAKE) -C "$(CURDIR)" dbt-seed
	$(MAKE) -C "$(CURDIR)" dbt-run-snapshots
	$(MAKE) -C "$(CURDIR)" dbt-run
	$(MAKE) -C "$(CURDIR)" dbt-test
	$(MAKE) -C "$(CURDIR)" dbt-docs-generate

all:
	$(MAKE) -C "$(CURDIR)" build
	$(MAKE) -C "$(CURDIR)" up
	$(MAKE) -C "$(CURDIR)" pipeline
	@echo ""
	@echo "========================================="
	@echo " Full Big Data pipeline completed"
	@echo "========================================="

# ============================================================
# Quick rebuild and test
# ============================================================

rebuild:
	$(MAKE) -C "$(CURDIR)" up
	$(MAKE) -C "$(CURDIR)" pipeline
	@echo ""
	@echo "========================================="
	@echo " Rebuild and test completed"
	@echo "========================================="
