from tests.__classes__ import BaseTest

test = BaseTest("Basic health check")
test.create_script("return ctx, args")
test.create_script("local ok, scr = game.script.load('test.test'); return ok, scr, scr.run(args)", name = "test.test2")

test.new_execution("CLI called no args")
test.expect_return({'caller':'test','cli':True})
test.expect_ok()

test.new_execution("CLI called with args", args = "ok")
test.expect_return([{'caller':'test','cli':True},"ok"])
test.expect_ok()

test.new_execution("Subscript called no args", script = "test.test2")
test.expect_return([True, {'system': False, 'accessLevel': 3, 'owner': 'test', 'name': 'test.test', 'hookable': False, 'run': {'$error': "type 'function' is not supported by JSON."}}, {'callingScript': 'test.test2', 'caller': 'test', 'cli': False}])
test.expect_ok()

test.new_execution("Subscript called with args", script = "test.test2", args = "ok")
test.expect_return([True, {'system': False, 'accessLevel': 3, 'owner': 'test', 'name': 'test.test', 'hookable': False, 'run': {'$error': "type 'function' is not supported by JSON."}}, {'callingScript': 'test.test2', 'caller': 'test', 'cli': False}, 'ok'])
test.expect_ok()
