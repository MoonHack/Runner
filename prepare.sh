#!/bin/sh
set -e
if [ ! -d "/sys/fs/cgroup/memory/$USER" ];
then
	U="$USER"
	sudo mkdir -p "/sys/fs/cgroup/memory/$U" || true
	sudo chown -R "$U:$U" "/sys/fs/cgroup/memory/$U" || true
fi
rmdir "/sys/fs/cgroup/memory/$USER/moonhack_cg_"* || true
