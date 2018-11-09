#!/bin/sh
set -xe

ORIG_USER="$USER"
export USER=root
rm -rf /root/.cache
luarocks-5.1 install dkjson
luarocks-5.1 install lua-mongo

export LUA_PATH=/root/Runner/LuaJIT/src/?.lua
export LUA_CPATH=/root/Runner/LuaJIT/src/?.so

cd /root/Runner/LuaJIT
make clean

cd /root/Runner/build
cmake -DCMAKE_BUILD_TYPE=Release ..
make

unset LUA_PATH
unset LUA_CPATH
export USER="$ORIG_USER"

