#!/bin/sh
set -e

export U="runner"

mkdir -p "/sys/fs/cgroup/memory/$U" || true
chown -R "$U:$U" "/sys/fs/cgroup/memory/$U" || true

exec ./simple_master "$RUNNER_COUNT"

