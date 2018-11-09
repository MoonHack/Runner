#!/bin/sh
set -e

mkdir -p /opt/runnertmp/root

umount /sys/fs/cgroup/memory || true
mount -o rw,nosuid,nodev,noexec,relatime,memory -t cgroup cgroup /sys/fs/cgroup/memory || true

export U="runner"
export UID="$(id -u "$U")"

mkdir -p "/sys/fs/cgroup/memory/$U" || true
chown -R "$U:$U" "/sys/fs/cgroup/memory/$U" || true

export USER="$U"
exec ./simple_master "$RUNNER_COUNT" "$UID"

