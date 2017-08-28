from uuid import uuid4
from sys import argv
import json
import zmq

# Dummy script to manually trigger a script run like: python3 run.py user user.script '{}'

context = zmq.Context(1)
socket = context.socket(zmq.REQ)
socket.connect("tcp://127.0.0.1:5556")
socket.setsockopt(zmq.LINGER, 0)
socket.setsockopt(zmq.RCVTIMEO, 60000)
socket.setsockopt(zmq.SNDTIMEO, 60000)

print("OK")

run_id = str(uuid4())
caller = argv[1]
script = argv[2]
args = argv[3]

print(socket.send_string(json.dumps({
	'run_id': run_id,
	'caller': caller,
	'script': script,
	'args': args
})))
print("OK")
print(socket.recv_string())
