#!/usr/bin/env bash
set -euo pipefail

# These paths match hdfs-site.xml and the namenode-format volume mounts.
name_dir=/tmp/hadoop-hadoop/dfs/name
data_dir=/tmp/hadoop-hadoop/dfs/data

if [ -f "$name_dir/current/VERSION" ]; then
    echo "NameNode already initialized; preserving the existing filesystem."
    exit 0
fi

# A missing VERSION file does not prove that this is a new installation.
# Refuse partial NameNode metadata and orphaned DataNode blocks alike.
for storage_dir in "$name_dir" "$data_dir"; do
    if [ ! -d "$storage_dir" ]; then
        echo "Required storage mount is missing: $storage_dir" >&2
        exit 1
    fi
    contents=$(find "$storage_dir" -mindepth 1 -maxdepth 1 -print -quit)
    if [ -n "$contents" ]; then
        echo "Refusing to format: $storage_dir is not empty. Recover the existing storage first." >&2
        exit 1
    fi
done

echo "Initializing an empty HDFS NameNode."
hdfs namenode -format -nonInteractive
