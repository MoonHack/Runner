from tests.__classes__ import BaseTest

test = BaseTest('Memory limit')
test.create_script('print("ok"); local a = {}; while true do table.insert(a, "ok") end; return a')
test.create_script('''
	local _L = "" --secureRandom.bytes(102400)
	local un = 0
	local u = resources.memory.getUsage()
	local ln = 0
	local l =  _L:len()
	for i = 0, 10 do
		_L = _L .. secureRandom.bytes(102400)
		ln = string.len(_L)
		util.sleep(0.1)
		un = resources.memory.getUsage()
		if un <= u or ln <= l then
			return false, i, un, u, ln, l
		end
		--l = ln
		--u = un
	end
	return true
''', name = "test.test2")

test.new_execution('Killer')
test.expect_print('ok')
test.expect_exitcode('SOFT_MEMORY_LIMIT')

test.new_execution('Monitor', script = "test.test2")
test.expect_return(True)
test.expect_exitcode('OK')
