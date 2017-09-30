from tests.__classes__ import BaseTest

test = BaseTest('Soft timeout (Lua)')
test.create_script('while true do util.sleep(400) print("ok") end')
test.new_execution()
for i in range(0, 12):
	test.expect_print('ok')
test.expect_exitcode('SOFT_TIMEOUT')
test.slow = True
