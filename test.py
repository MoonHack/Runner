from pymongo import MongoClient
from os import path, listdir, environ
from importlib import import_module

noSlow = False
try:
	noSlow = not not environ["TEST_NOSLOW"]
except:
	pass

mongoDb = MongoClient("mongodb://127.0.0.1").moonhack_core

mypath = path.abspath("./%s/tests/" % path.dirname(__file__))
for module in listdir(mypath):
	if module == '__init__.py' or module[-3:] != '.py' or (module[0:2] == "__" and module[-5:-3] == "__"):
		continue
	modname = "tests.%s" % module[:-3]
	test = import_module(modname).test
	if not test.name:
		test.name = module[:-3]
	if test.slow and noSlow:
		print("[SKIP] %s: Test slow, but TEST_NOSLOW set" % test.name)
		continue
	test.run(mongoDb)
