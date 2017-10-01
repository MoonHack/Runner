from tests.__classes__ import BaseTest

test = BaseTest('Sanity of cache')
test.create_script('''
	_L = (_L or 0) + 1
	print(_L)
''', name = 'test.test2')
test.create_script('''
	local ok, sub = game.script.load("test.test2")
	sub.run()
	sub.run()
''')

for i in range(0, 2):
	test.new_execution('Run %d' % (i+1))
	test.expect_print(1, initial = False, script = 'test.test2')
	test.expect_print(2, initial = False, script = 'test.test2')
	test.expect_return_nodata()
	test.expect_ok()
