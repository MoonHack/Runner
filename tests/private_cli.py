from tests.__classes__ import BaseTest

test = BaseTest()
test.create_script("return 'ok'", accessLevel = 1)
test.new_execution()
test.expect_return("ok")
test.expect_ok()
