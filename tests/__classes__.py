from json import dumps as json_dumps, loads as json_loads
from subprocess import Popen, PIPE

class TestQuery:
	def __init__(self, data, collection = 'scripts', operation = 'insert_one'):
		self.data = data
		self.collection = collection
		self.operation = operation

class BaseTest:
	def __init__(self, name = None):
		self.name = name
		self.user = []
		self.script = []
		self.args = []
		self.result = []
		self.queries = []
		self.names = []
		self.curtest = -1
		self.slow = False

	def new_execution(self, name = '', user = 'test', script = 'test.test', args = None):
		if name == '':
			name = str(self.curtest + 2)
		self.user.append(user)
		self.script.append(script)
		self.args.append(args)
		self.result.append([])
		self.names.append(name)
		self.curtest += 1

	def expect_exitcode(self, res):
		self.result[self.curtest].append('\x01%s' % res)

	def expect_ok(self):
		self.expect_exitcode('OK')

	def expect_print(self, result, script = None, initial = True):
		if script == None:
			script = self.script[self.curtest]
		self.result[self.curtest].append({
			'type': 'print',
			'script': script,
			'data': result,
			'initial': initial,
		})

	def expect_return_nodata(self):
		self.result[self.curtest].append({
			'type': 'return',
			'script': self.script[self.curtest],
		})

	def expect_return(self, result):
		self.result[self.curtest].append({
			'type': 'return',
			'script': self.script[self.curtest],
			'data': result,
		})

	def expect_error(self, result):
		self.result[self.curtest].append({
			'type': 'error',
			'script': self.script[self.curtest],
			'data': result,
		})

	def create_script(self, source, name = 'test.test', accessLevel = 3):
		self.queries.append(TestQuery({
			'name': name,
			'owner': name.split('.')[0],
			'accessLevel': accessLevel,
			'code': 'function(ctx, args) %s end' % source,
			'codeDate': 'now',
		}))

	def run(self, mongoDb):
		mongoDb.users.remove({})
		mongoDb.scripts.remove({})
		mongoDb.users.insert({
			'name': 'test',
			'balance': 0,
		})
		for q in self.queries:
			m = getattr(mongoDb[q.collection], q.operation)
			m(q.data)
		del q, m, mongoDb

		isCorrect = True
		for i in range(0, self.curtest + 1):
			correct = self.result[i]
			got = self.exec(self.user[i], self.script[i], json_dumps(self.args[i]))
			correct.append('[EOF]')
			got.append(b'[EOF]')
			for j in range(0, max(len(got),len(correct))):
				gotO = got[j].decode('utf-8').strip(' \t\n\r')
				correctO = correct[j]
				if type(correctO) is not str:
					try:
						gotO = json_loads(gotO)
					except:
						pass
				if gotO != correctO:
					isCorrect = False
					print('[FAIL] %s -> %s: t=%d,l=%d\nWant: %s\nGot:  %s' % (self.name, self.names[i], i, j, correctO, gotO))
					break
			if isCorrect:
				print('[OK] %s -> %s' % (self.name, self.names[i]))
			else:
				break
		return isCorrect

	def exec(self, user, script, args):
		args = ('./build/run', user, script, args)
		popen = Popen(args, stdout=PIPE)
		popen.wait()
		return popen.stdout.readlines()
