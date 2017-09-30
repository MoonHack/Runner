from tests.__classes__ import BaseTest

test = BaseTest('_G table write protection')
test.create_script('''
	local x = _G
	for _, v in next, args.p do
		x = x[v]
	end
	x[args.k] = args.v or true
	print(x)
''')
test.create_script('return _G.game == game, _G == _G._G, _G[args]', name = 'test.test2')
test.create_script('meow = true; return meow', name = "test.test3")

test.new_execution('Read non-existant, verify _G table basics', script = 'test.test2', args = 'meow')
test.expect_return([True,True])
test.expect_ok()

test.new_execution('Write new var fixed name', script = "test.test3")
test.expect_return_nodata()
test.expect_ok()

test.new_execution('Overwrite game.script.load', args = {'p': ['game', 'script'], 'k': 'load'})
test.expect_error('ERROR: table is readonly\n\ttest.test:1: main chunk')
test.expect_ok()
