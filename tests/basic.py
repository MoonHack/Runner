from tests.__classes__ import BaseTest

test = BaseTest("Basic health check")
test.create_script("return 'ok'")
test.new_execution()
test.expect_return("ok")
test.expect_ok()
