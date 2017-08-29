#!/bin/sh
set -e
compile() {
	gcc "$1.c" -O3 -o "$1" -lzmq
	strip "$1"
}
compile main
compile router
compile worker

