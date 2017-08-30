#!/bin/sh
set -e
if [ ! -d "/sys/fs/cgroup/memory/$USER" ];
then
	U="$USER"
	sudo user_cgroups "$U"
fi
cd build
cmake ..
make
cd ..
rmdir "/sys/fs/cgroup/memory/$USER/moonhack_cg_"* || true
exec ./simple_master 64 "tcp://*:5556"
