from tests.__classes__ import BaseTest

test = BaseTest()
test.create_script("return 'ok'", name ="test2.test", accessLevel = 1)
test.new_execution(script = "test2.test")
test.expect_error("Cannot load private script of different user")
test.expect_ok()
