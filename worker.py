import signal
import os
import json
from lupa import LuaRuntime
from cgroups import Cgroup
from gc import collect as gc_collect

#TODO: CONFIG THIS
task_timeout = 7
task_memory_limit = 32 # 8MB is about the baseline to be able to run simple scripts

cgroup = Cgroup('moonhack_cg_%d' % os.getpid())
cgroup.set_memory_limit(task_memory_limit)

os.chdir('lua')
lua = LuaRuntime(register_eval = False, register_builtins = False)
file = open('main.lua', 'r')
lua_progs = lua.execute(file.read())
lua_main = lua_progs[1]
#lua_flush_caches = lua_progs[2]
file.close()

lua_is_protected = 0
task_killed = False
task_alive = True
def runlua_sig(signum, frame):
	global task_alive
	global task_killed
	if task_alive and not lua_is_protected <= 0:
		task_killed = True
		os.kill(pid, signal.SIGTERM)

def lua_enter_protected():
	global lua_is_protected
	lua_is_protected += 1
	if lua_is_protected == 1:
		signal.signal(signal.SIGTERM, signal.SIG_IGN)
		cgroup.set_memory_limit(1024)

def lua_leave_protected():
	global lua_is_protected
	global cgroup
	lua_is_protected -= 1
	if lua_is_protected == 0:
		signal.signal(signal.SIGTERM, signal.SIG_DFL)
		cgroup.set_memory_limit(task_memory_limit)
	elif lua_is_protected < 0:
		raise 'Protection level subzero'

lua_progs[2](lua_enter_protected, lua_leave_protected)
lua_progs = None

def runlua(caller, script, args):
	global task_alive
	global task_killed
	global cgroup

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

		cgroup.add(os.getpid())
		lua_main(caller, script, args)
		exit(1)
	elif pid > 0:
		os.close(wpipe)
		os.close(wpipe_err)
		prpipe = os.fdopen(rpipe, 'r')
		prpipe_err = os.fdopen(rpipe_err, 'r')

		task_killed = False
		task_alive = True

		signal.signal(signal.SIGALRM, runlua_sig)
		signal.alarm(task_timeout)

		errcode = os.waitpid(pid, 0)
		signal.alarm(0)
		task_alive = False
		result = ''

		if task_killed:
			result = [{'ok': False, 'data': 'Script hard-killed after 5 second timeout'}]
		elif errcode[1] != 0:
			if errcode[1] == 9:
				result = [{'ok': False, 'data': 'Script used too much memory and was terminated'}]
			else:
				result = [{'ok': False, 'data': 'Script caused internal error. Admins have been notified'}]
				print(errcode[1])
				print(prpipe.read())
				print(prpipe_err.read())
		else:
			try:
				result = []
				for line in prpipe:
					if line != '\n':
						result.append(json.loads(line))
			except json.decoder.JSONDecodeError as e:
				result = [{'ok': False, 'data': 'Script caused internal error. Admins have been notified'}]
				print(prpipe_err.read())
				print(e)

		os.close(rpipe)
		os.close(rpipe_err)

		return result
	else:
		exit(1)

def main(socket):
	lua.eval('collectgarbage()')
	gc_collect()
	while True:
		msg = json.loads(socket.recv_string())
		caller = msg['caller']
		script = msg['script']
		run_id = msg['run_id']
		result = runlua(caller, script, msg['args'])
		socket.send_string(json.dumps({'caller': caller, 'run_id': run_id, 'script': script, 'result': result}))
