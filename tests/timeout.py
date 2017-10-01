from tests.__classes__ import BaseTest

test = BaseTest('Timeout')
test.slow = True

test.create_script('''
	while true do
		util.sleep(400)
		print("ok")
	end
''')
test.create_script('''
	print("ok")
	util.sleep(100000)
''', name = 'test.test2')

test.new_execution('Soft (Lua)')
for i in range(0, 12):
	test.expect_print('ok')
test.expect_exitcode('SOFT_TIMEOUT')

test.new_execution('Hard (C)', script = 'test.test2')
test.expect_print('ok')
test.expect_exitcode('HARD_TIMEOUT')
