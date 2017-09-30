from tests.__classes__ import BaseTest

test = BaseTest('Access levels')

test.create_script('return "ok"', accessLevel = 1)
test.create_script('return "ok"', name ='test2.test1', accessLevel = 1)
test.create_script('return "ok"', name ='test2.test2', accessLevel = 2)
test.create_script('return "ok"', name ='test2.test3', accessLevel = 3)
test.create_script('return game.script.load("test.test")', name ='test.test1')
test.create_script('return game.script.load("test2.test1")', name ='test.test2')
test.create_script('return game.script.load("test2.test1", game.script.LOAD_ONLY_INFORMATION)', name ='test.test3')
test.create_script('return game.script.load("test2.test2")', name ='test.test4', accessLevel = 1)
test.create_script('return game.script.load("test2.test3")', name ='test.test5', accessLevel = 2)

test.new_execution(name = 'Run OWNED PRIVATE')
test.expect_return('ok')
test.expect_ok()

test.new_execution(name = 'Run UNOWNED PRIVATE', script = 'test2.test1')
test.expect_error('Cannot load private script of different user')
test.expect_ok()

test.new_execution(name = 'loadscript OWNED PRIVATE with exec', script = 'test.test1')
test.expect_return([True, {'owner': 'test', 'hookable': False, 'accessLevel': 1, 'run': {'$error': 'type \'function\' is not supported by JSON.'}, 'system': False, 'name': 'test.test'}])
test.expect_ok()

test.new_execution(name = 'loadscript UNOWNED PRIVATE with exec', script = 'test.test2')
test.expect_return([False, 'Cannot load private script of different user'])
test.expect_ok()

test.new_execution(name = 'loadscript UNOWNED PRIVATE without exec', script = 'test.test3')
test.expect_return([True, {'owner': 'test2', 'hookable': False, 'accessLevel': 1, 'system': False, 'name': 'test2.test1'}])
test.expect_ok()

test.new_execution(name = 'loadscript UNOWNED HIDDEN', script = 'test.test4')
test.expect_return([True, {'owner': 'test2', 'hookable': False, 'accessLevel': 2, 'run': {'$error': 'type \'function\' is not supported by JSON.'}, 'system': False, 'name': 'test2.test2'}])
test.expect_ok()

test.new_execution(name = 'loadscript UNOWNED PUBLIC', script = 'test.test5')
test.expect_return([True, {'owner': 'test2', 'hookable': False, 'accessLevel': 3, 'run': {'$error': 'type \'function\' is not supported by JSON.'}, 'system': False, 'name': 'test2.test3'}])
test.expect_ok()

test.new_execution(name = 'scripts.list type=public shows PUBLIC only', script = 'scripts.list', args = { 'type': 'public' })
test.expect_return([True, [{'owner': 'test2', 'accessLevel': 3, 'name': 'test2.test3'}, {'owner': 'test', 'accessLevel': 3, 'name': 'test.test1'}, {'owner': 'test', 'accessLevel': 3, 'name': 'test.test2'}, {'owner': 'test', 'accessLevel': 3, 'name': 'test.test3'}]])
test.expect_ok()

test.new_execution(name = 'scripts.list type=mine shows OWNED only', script = 'scripts.list', args = { 'type': 'mine' })
test.expect_return([True, [{'name': 'test.test', 'owner': 'test', 'accessLevel': 1}, {'name': 'test.test1', 'owner': 'test', 'accessLevel': 3}, {'name': 'test.test2', 'owner': 'test', 'accessLevel': 3}, {'name': 'test.test3', 'owner': 'test', 'accessLevel': 3}, {'name': 'test.test4', 'owner': 'test', 'accessLevel': 1}, {'name': 'test.test5', 'owner': 'test', 'accessLevel': 2}]])
test.expect_ok()
