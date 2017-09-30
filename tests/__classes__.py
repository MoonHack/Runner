from json import dumps as json_dumps, loads as json_loads
from subprocess import Popen, PIPE

class TestQuery:
	def __init__(self, data, collection = "scripts", operation = "insert_one"):
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
		self.curtest = -1
		self.slow = False

	def new_execution(self, user = "test", script = "test.test", args = None):
		self.user.append(user)
		self.script.append(script)
		self.args.append(args)
		self.result.append([])
		self.curtest += 1

	def expect_exitcode(self, res):
		self.result[self.curtest].append("\x01%s" % res)

	def expect_ok(self):
		self.expect_exitcode("OK")

	def expect_print(self, result, script = "test.test", initial = True):
		self.result[self.curtest].append({
			"type": "print",
			"script": script,
			"data": result,
			"initial": initial,
		})

	def expect_return_nodata(self):
		self.result[self.curtest].append({
			"type": "return",
			"script": self.script[self.curtest],
		})

	def expect_return(self, result):
		self.result[self.curtest].append({
			"type": "return",
			"script": self.script[self.curtest],
			"data": result,
		})

	def expect_error(self, result):
		self.result[self.curtest].append({
			"type": "error",
			"script": self.script[self.curtest],
			"data": result,
		})

	def create_script(self, source, name = "test.test", accessLevel = 3):
		self.queries.append(TestQuery({
			"name": name,
			"owner": name.split(".")[0],
			"accessLevel": accessLevel,
			"code": "function(ctx, args) %s end" % source,
			"codeDate": "now",
		}))

	def run(self, mongoDb):
		mongoDb.users.remove({})
		mongoDb.scripts.remove({})
		mongoDb.users.insert({
			"name": "test",
			"balance": 0,
		})
		for q in self.queries:
			mongoDb[q.collection].insert_one(q.data)

		isCorrect = True
		for i in range(0, self.curtest + 1):
			correct = self.result[i]
			got = self.exec(self.user[i], self.script[i], json_dumps(self.args[i]))
			for j in range(0, len(got)):
				got[j] = got[j].decode("utf-8")
				correctO = correct[j]
				gotO = got[j].strip(' \t\n\r')
				if type(correctO) is not str:
					gotO = json_loads(gotO)
				if gotO != correctO:
					isCorrect = False
					print("[FAIL] %s,t=%d,l=%d\nWant: %s\nGot:  %s" % (self.name, i, j, correctO, gotO))
					break
			if isCorrect:
				print("[OK] %s" % self.name)
			else:
				break
		return isCorrect

	def exec(self, user, script, args):
		args = ("./build/run", user, script, args)
		popen = Popen(args, stdout=PIPE)
		popen.wait()
		return popen.stdout.readlines()
