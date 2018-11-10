#!/bin/sh
set -e

mkdir -p /opt/runnertmp/root

export U="runner"
export UID="$(id -u "$U")"

chown -R "$U:$U" "$CGROUPDIR"

exec ./simple_master "$RUNNER_COUNT" "$UID"

