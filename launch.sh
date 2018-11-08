#!/bin/sh
set -e
. ./devconf.sh

typ="Debug"
if [ ! -z "$1" ]
then
	typ="$1"
fi
. ./prepare.sh
cd build
cmake "-DCMAKE_BUILD_TYPE=$typ" ..
make

exec ./simple_master 1
