from tests.__classes__ import BaseTest

test = BaseTest()
test.create_script("meow = true")
test.new_execution()
test.expect_error("ERROR: Read-Only\n\t=[C]:-1: main chunk\n\ttest.test:1: main chunk")
test.expect_ok()
