import signal
import os
import json
from lupa import LuaRuntime

os.chdir("lua")
lua = LuaRuntime(register_eval = False, register_builtins = False)
file = open("main.lua", "r")
luaProgs = lua.execute(file.read())
luaMain = luaProgs[1]
luaFlushCaches = luaProgs[2]
file.close()

task_timeout = 7

def runlua(caller, script, args):
	rpipe, wpipe = os.pipe()
	rpipe_err, wpipe_err = os.pipe()
	pid = os.fork()
	if pid == 0:
		os.close(rpipe)
		os.close(rpipe_err)
		os.dup2(wpipe, 1)
		os.close(wpipe)
		os.dup2(wpipe_err, 2)
		os.close(wpipe_err)

		luaMain(caller, script, args)
		exit(0)
	elif pid > 0:
		os.close(wpipe)
		os.close(wpipe_err)
		prpipe = os.fdopen(rpipe, 'r')
		prpipe_err = os.fdopen(rpipe_err, 'r')
		task_killed = False
		task_alive = True
		def runlua_sig(signum, frame):
			nonlocal task_alive
			nonlocal task_killed
			if task_alive:
				task_killed = True
				os.kill(pid, signal.SIGKILL)
		signal.signal(signal.SIGALRM, runlua_sig)
		signal.alarm(task_timeout)
		errcode = os.waitpid(pid, 0)
		task_alive = False
		result = ''
		luaFlushCaches()
		if task_killed:
			result = [{'ok': False, 'data': "Script hard-killed after 5 second timeout"}]
		elif errcode[1] != 0:
			result = [{'ok': False, 'data': "Script caused internal error. Admins have been notified"}]
			print(prpipe.read())
			print(prpipe_err.read())
		else:
			data = prpipe.readlines()
			try:
				result = []
				for line in data:
					if line == "":
						return
					result.append(json.loads(line))
			except e:
				print(data)
				print(prpipe_err.read())
				print(e)
				result = [{'ok': False, 'data': "Script caused internal error. Admins have been notified"}]

		os.close(rpipe)
		os.close(rpipe_err)

		return result
	else:
		exit(1)


def main(socket):
	while True:
		msg = json.loads(socket.recv_string())
		caller = msg['caller']
		script = msg['script']
		run_id = msg['run_id']
		print("Got run", caller, script, run_id)
		result = runlua(caller, script, msg['args'])
		socket.send_string(json.dumps({'caller': caller, 'run_id': run_id, 'script': script, 'result': result}))
