from tests.__classes__ import BaseTest

test = BaseTest()
test.create_script("print(\"ok\"); local a = {}; while true do table.insert(a, \"ok\") end")
test.new_execution()
test.expect_print("ok")
test.expect_exitcode("MEMORY_LIMIT")
