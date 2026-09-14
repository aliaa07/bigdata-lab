#!/usr/bin/env bash
set -euo pipefail

# Run in a disposable Hadoop container with no project storage volumes.
# Refuse to touch any pre-existing storage, even in a test container.
name_dir=/tmp/hadoop-hadoop/dfs/name
data_dir=/tmp/hadoop-hadoop/dfs/data
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd)
for path in "$name_dir" "$data_dir"; do
    if [ -e "$path" ]; then
        echo "Tests require absent storage directories: $path" >&2
        exit 1
    fi
done

reset_fixture() {
    # Only these two directories, created by this test, are removed.
    rm -rf -- "$name_dir" "$data_dir"
    mkdir -p "$name_dir" "$data_dir"
}

expect_refusal() {
    if bash "$script_dir/init-namenode.sh"; then
        echo "FAIL: initialization unexpectedly succeeded" >&2
        exit 1
    fi
    test ! -e "$name_dir/current/VERSION"
}

mkdir -p "$name_dir" "$data_dir"
bash "$script_dir/init-namenode.sh"
test -s "$name_dir/current/VERSION"
before=$(sha256sum "$name_dir/current/VERSION")
# An initialized installation may already have DataNode blocks.
echo keep-data > "$data_dir/existing-block"
bash "$script_dir/init-namenode.sh"
test "$before" = "$(sha256sum "$name_dir/current/VERSION")"
test "$(cat "$data_dir/existing-block")" = keep-data
echo "PASS: real format of empty storage; second init preserves metadata and blocks"

reset_fixture
echo keep-metadata > "$name_dir/partial-metadata"
expect_refusal
test "$(cat "$name_dir/partial-metadata")" = keep-metadata
echo "PASS: partial NameNode storage is preserved and rejected"

reset_fixture
echo keep-block > "$data_dir/orphaned-block"
expect_refusal
test "$(cat "$data_dir/orphaned-block")" = keep-block
echo "PASS: orphaned DataNode storage is preserved and rejected"

reset_fixture
rmdir "$data_dir"
expect_refusal
echo "PASS: a missing DataNode mount is rejected"

reset_fixture
mkdir "$name_dir/.hidden-metadata"
expect_refusal
test -d "$name_dir/.hidden-metadata"
echo "PASS: hidden existing storage is rejected"
