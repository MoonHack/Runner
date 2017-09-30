from tests.__classes__ import BaseTest

test = BaseTest("Private scripts")

test.create_script("return 'ok'", accessLevel = 1)
test.create_script("return 'ok'", name ="test2.test", accessLevel = 1)

test.new_execution(name = "Run owned")
test.expect_return("ok")
test.expect_ok()

test.new_execution(name = "Run unowned", script = "test2.test")
test.expect_error("Cannot load private script of different user")
test.expect_ok()
