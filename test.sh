#!/bin/sh
set -e
if [ ! -d "/sys/fs/cgroup/memory/$USER" ];
then
	U="$USER"
	sudo user_cgroups "$U"
fi
./make.sh
rmdir "/sys/fs/cgroup/memory/$USER/moonhack_cg_"* || true
exec ./bin/simple_master "tcp://*:5556"
