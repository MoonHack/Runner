#!/bin/sh
set -e
. ./prepare.sh
cd build
cmake -DCMAKE_BUILD_TYPE=Debug ..
make
exec ./simple_master 1
