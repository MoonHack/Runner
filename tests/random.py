from tests.__classes__ import BaseTest

test = BaseTest('Randomness check')
test.create_script('''
	local x = math.random()
	math.randomseed(0)
	local a1 = math.random()
	math.randomseed(0)
	local a2 = math.random()
	return x == a1, x == a2, a1 == a2
''')

test.new_execution('Ensure stuff works')
test.expect_return([False, False, True])
test.expect_ok()
