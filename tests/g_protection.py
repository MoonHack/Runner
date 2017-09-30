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
test.create_script('''
	local x = _G
	for _, v in next, args.p do
		x = x[v]
	end
	rawset(x, args.k, args.v or true)
	print(x)
''', name = "test.test2")
test.create_script('return _G.game == game, _G == _G._G, _G[args]', name = 'test.test3')
test.create_script('local g = game; game = nil; return game == g, _G.game == g, type(game), type(_G.game)', name = "test.test4")

test.new_execution('Read non-existant, verify _G table basics', script = 'test.test3', args = 'meow')
test.expect_return([True,True])
test.expect_ok()

test.new_execution('Write new var fixed name', script = "test.test4")
test.expect_return([True,True,'table','table'])
test.expect_ok()

test.new_execution('Overwrite game.script.load', args = {'p': ['game', 'script'], 'k': 'load'})
test.expect_error('ERROR: table is readonly\n\ttest.test:1: main chunk')
test.expect_ok()

test.new_execution('Overwrite rawset game.script.load', args = {'p': ['game', 'script'], 'k': 'load'}, script = "test.test2")
test.expect_error('ERROR: table is readonly\n\t=[C]:-1: global function rawset\n\ttest.test2:1: main chunk')
test.expect_ok()
