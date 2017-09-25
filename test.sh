#!/bin/sh
source prepare.sh
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make
exec ./simple_master 1
