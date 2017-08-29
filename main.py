#!/usr/bin/env python3

import zmq
import os
import signal
from worker import main as worker_main
from time import sleep
from sys import executable as sys_executable
from gc import collect as gc_collect

if __name__ != '__main__':
    raise Exception('Please run me, not import')

# TODO: CONFIG THIS
worker_count = 64
zmq_threads = 4

ipc_socket = 'ipc:///tmp/moonhack-master-to-workers'

def zmq_setopt(socket):
	socket.setsockopt(zmq.LINGER, 0)
	socket.setsockopt(zmq.RCVTIMEO, 60000)
	socket.setsockopt(zmq.SNDTIMEO, 60000)

def all_exit(signum, frame):
	os.kill(-os.getpid(), signal.SIGTERM)

def noop_hdlr(signum, frame):
	pass

worker_pids = []

def spawn_worker():
	pid = os.fork()
	if pid == 0:
		try:
			signal.signal(signal.SIGINT, signal.SIG_IGN)
			signal.signal(signal.SIGHUP, signal.SIG_IGN)
			signal.signal(signal.SIGCHLD, noop_hdlr)
			
			context = zmq.Context(1)
			socket = context.socket(zmq.REP)
			socket.connect(ipc_socket)
			socket.setsockopt(zmq.LINGER, 0)
			socket.setsockopt(zmq.RCVTIMEO, -1)
			socket.setsockopt(zmq.SNDTIMEO, 5000)

			gc_collect()
			return worker_main(socket)
		finally:
			exit(1)
	elif pid > 0:
		return pid
	else:
		raise 'Could not fork'	

def sigchld_recvd(signum, frame):
	pid, status = os.waitpid(-1, os.WNOHANG|os.WUNTRACED|os.WCONTINUED)
	if os.WIFCONTINUED(status) or os.WIFSTOPPED(status):
		return
	if os.WIFSIGNALED(status) or os.WIFEXITED(status):
		try:
			pos = worker_pids.index(pid)
			worker_pids[pos] = spawn_worker()
		except ValueError:
			pass

signal.signal(signal.SIGCHLD, sigchld_recvd)
signal.signal(signal.SIGINT, all_exit)
signal.signal(signal.SIGHUP, all_exit)

gc_collect()

for worker_id in range(0, worker_count):
	worker_pids.append(spawn_worker())

# ZMQ listener
print('Listening...')
context = zmq.Context(zmq_threads)

frontend = context.socket(zmq.XREP)
frontend.bind('tcp://*:5556')
zmq_setopt(frontend)
frontend.setsockopt(zmq.RCVTIMEO, -1)
frontend.setsockopt(zmq.SNDTIMEO, 5000)

backend = context.socket(zmq.XREQ)
backend.bind(ipc_socket)
zmq_setopt(backend)
backend.setsockopt(zmq.RCVTIMEO, 10000)

zmq.device(zmq.QUEUE, frontend, backend)
exit(1)
