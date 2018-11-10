#!/bin/sh
set -e

mkdir -p /opt/runnertmp/root

export U="runner"
export UID="$(id -u "$U")"

export CGROUPDIR="$(hostname)"

mkdir -p "/sys/fs/cgroup/memory/$CGROUPDIR" || true
chown -R "$U:$U" "/sys/fs/cgroup/memory/$CGROUPDIR" || true

exec ./simple_master "$RUNNER_COUNT" "$UID"

