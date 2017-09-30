#!/bin/bash
set -e

pkill -KILL -fe worker >/dev/null 2>/dev/null || true
pkill -KILL -fe simple_master >/dev/null 2>/dev/null || true

EXPECT_OK=$'\1''OK'

./launch.sh "$1" > /dev/null &
SUBPID="$!"
sleep 0.5
killsub() {
	kill -STOP "$SUBPID"
	pkill -STOP -P "$SUBPID"
	pkill -KILL -P "$SUBPID"
	kill -KILL "$SUBPID"
}

runtest() {
	TEST_USER=""
	TEST_ARGS=""
	TEST_SLOW=0

	. "./$1"

	if [ ! -z "$TEST_NOSLOW" ]
	then
		if [ "$TEST_SLOW" == "1" ]
		then
			echo "[SKIP] $1: Slow test"
			return
		fi
	fi

	echo "db.scripts.remove({}); db.users.remove({}); db.users.insert({name:'test'}); $TEST_DB;" > tmp.db.js
	mongo moonhack_core < tmp.db.js > /dev/null
	rm -f tmp.db.js

	if [ -z "$TEST_USER" ]
	then
		TEST_USER="test"
	fi

	TEST_RESULT="$(./build/run "$TEST_USER" "$TEST_SCRIPT" "$TEST_ARGS")"
	if [ "$TEST_RESULT" == "$TEST_EXPECT" ]
	then
		echo "[OK] $1"
	else
		echo "[ERROR] $1"
		echo "Expected:"
		echo "$TEST_EXPECT"
		echo "Got:"
		echo "$TEST_RESULT"
		exit 1
	fi
}

echo "BEGIN TESTING"

for f in tests/*.sh
do
	runtest "$f"
done

killsub
