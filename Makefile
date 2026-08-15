# ============================================================
# Big Data Lakehouse - Makefile
# Pipeline orchestration
# ============================================================

.PHONY: help \
	init up ci-up normal-up down build \
	dbt-deps dbt-seed \
	dbt-run dbt-run-staging dbt-run-core dbt-run-marts dbt-run-snapshots \
	dbt-test dbt-docs dbt-docs-generate dbt-clean \
	all rebuild

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
	@echo "  init               - Initialize HDFS NameNode"
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
	@echo "  all                - Full pipeline"
	@echo "  rebuild            - Re-run dbt pipeline"

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

ci-up:
	@echo "Initializing bigdata network..."
	docker network create bigdata 2>/dev/null || true

	@echo "Starting Hadoop..."
	cd $(HADOOP_DIR) && docker compose up -d

	@echo "Formatting HDFS NameNode..."
	cd $(HADOOP_DIR) && docker compose run --rm namenode hdfs namenode -format -force

	@echo "Waiting for HDFS NameNode to be healthy..."
	@until (cd $(HADOOP_DIR) && docker compose exec -T namenode hdfs dfsadmin -report >/dev/null 2>&1); do \
		echo "  ...still waiting on HDFS"; \
		sleep 3; \
	done
	@echo "HDFS NameNode initialization completed."

	@echo "Starting PySpark..."
	cd $(PYSPARK_DIR) && docker compose up -d

	@echo "Waiting for Spark Thrift Server to accept connections..."
	@until (cd $(PYSPARK_DIR) && docker compose exec -T spark-thrift bash -c "echo > /dev/tcp/localhost/10000" >/dev/null 2>&1); do \
		echo "  ...still waiting on Thrift Server"; \
		sleep 3; \
	done

	@echo "Big Data stack is ready."

normal-up:
	#docker network create bigdata 2>/dev/null || true

	@echo "Starting Hadoop..."
	cd $(HADOOP_DIR) && docker compose up -d

	@echo "Waiting for HDFS NameNode to be healthy..."
	@until (cd $(HADOOP_DIR) && docker compose exec -T namenode hdfs dfsadmin -report >/dev/null 2>&1); do \
		echo "  ...still waiting on HDFS"; \
		sleep 3; \
	done

	@echo "Starting PySpark..."
	cd $(PYSPARK_DIR) && docker compose up -d

	@echo "Waiting for Spark Thrift Server to accept connections..."
	@until (cd $(PYSPARK_DIR) && docker compose exec -T spark-thrift bash -c "echo > /dev/tcp/localhost/10000" >/dev/null 2>&1); do \
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
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt deps

dbt-seed:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt seed --select sample_flight_data

dbt-run:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt run

dbt-run-staging:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt run --select staging

dbt-run-core:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt run --select core

dbt-run-marts:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt run --select marts

dbt-run-snapshots:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt snapshot

dbt-test:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt test

dbt-docs-generate:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt docs generate

dbt-docs:
	cd $(PYSPARK_DIR) && docker compose exec -d dbt \
		sh -c "dbt docs generate && dbt docs serve --port 8080 --host 0.0.0.0"

	@echo "Waiting for dbt docs server..."
	@until docker compose exec -T dbt sh -c \
		"echo > /dev/tcp/localhost/8080" \
		>/dev/null 2>&1; do \
		sleep 1; \
	done

	@echo "dbt docs server is ready on port 8080"

dbt-clean:
	cd $(PYSPARK_DIR) && docker compose exec dbt dbt clean

# ============================================================
# Full pipeline
# ============================================================

all: build ci-up dbt-deps dbt-seed dbt-run-snapshots dbt-run dbt-test dbt-clean
	@echo ""
	@echo "========================================="
	@echo " Full Big Data pipeline completed"
	@echo "========================================="

# ============================================================
# Quick rebuild and test
# ============================================================

rebuild: build init up dbt-clean dbt-deps dbt-seed dbt-run dbt-test
	@echo ""
	@echo "========================================="
	@echo " Rebuild and test completed"
	@echo "========================================="