#!/bin/sh
set -e
compile() {
	x="$1"
	shift 1
	gcc "$x.c" -O3 -Wall -o "./bin/$x" -lzmq $@
	strip "./bin/$x"
}
rm -f ./bin/*
compile simple_master
compile router
compile worker `pkg-config --cflags luajit` `pkg-config --libs luajit`
compile run
