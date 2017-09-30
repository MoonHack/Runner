from tests.__classes__ import BaseTest

test = BaseTest('Hard timeout (C)')
test.create_script('print("ok") util.sleep(100000)')
test.new_execution()
test.expect_print('ok')
test.expect_exitcode('HARD_TIMEOUT')
test.slow = True
