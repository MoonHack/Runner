#!/bin/sh
set -e
compile() {
	x="$1"
	shift 1
	gcc "$x.c" -O3 -o "$x" -lzmq $@
	strip "$x"
}
compile main
compile router
compile worker -I/usr/include/luajit-2.0 -L/usr/lib/luajit-2.0 -lluajit-5.1
compile run
