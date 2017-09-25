#!/bin/sh
set -e
if [ ! -d "/sys/fs/cgroup/memory/$USER" ];
then
	U="$USER"
	sudo mkdir -p "/sys/fs/cgroup/memory/$U"
	sudo chown -R "$U:$U" "/sys/fs/cgroup/memory/$U"
fi
rmdir "/sys/fs/cgroup/memory/$USER/moonhack_cg_"* || true
