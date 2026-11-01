import contextlib
import io
import unittest

from device_test_suite import DEVICE_LOST, failures, run_scenarios

SCENARIOS = ['device_a_test.py', 'device_b_test.py', 'device_c_test.py']


class Recorder:
    """Stands in for adb and for the scenario processes; records what was asked."""

    def __init__(self, device_gone_after=None, codes=None):
        self.device_gone_after = device_gone_after
        self.codes = codes or {}
        self.checked = []
        self.ran = []

    def ensure(self, script):
        self.checked.append(script)
        return self.device_gone_after is None or len(self.checked) <= self.device_gone_after

    def execute(self, script):
        self.ran.append(script)
        return self.codes.get(script, 0)


class RunScenariosTest(unittest.TestCase):
    def test_runs_every_scenario_in_order_when_all_pass(self):
        recorder = Recorder()
        results = run_scenarios(SCENARIOS, ensure=recorder.ensure, execute=recorder.execute)
        self.assertEqual(results, {script: 0 for script in SCENARIOS})
        self.assertEqual(recorder.ran, SCENARIOS)
        self.assertEqual(failures(results), {})

    def test_a_failing_scenario_does_not_stop_the_ones_after_it(self):
        recorder = Recorder(codes={'device_b_test.py': 1})
        results = run_scenarios(SCENARIOS, ensure=recorder.ensure, execute=recorder.execute)
        self.assertEqual(recorder.ran, SCENARIOS)
        self.assertEqual(failures(results), {'device_b_test.py': 1})

    def test_a_lost_device_marks_the_rest_without_pretending_they_ran(self):
        recorder = Recorder(device_gone_after=2)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            results = run_scenarios(SCENARIOS, ensure=recorder.ensure, execute=recorder.execute)
        self.assertEqual(recorder.ran, SCENARIOS[:2])
        self.assertEqual(results, {'device_a_test.py': 0, 'device_b_test.py': 0, 'device_c_test.py': DEVICE_LOST})
        self.assertEqual(failures(results), {'device_c_test.py': DEVICE_LOST})
        self.assertIn('device_c_test.py', output.getvalue())

    def test_scenarios_that_never_ran_still_block_release(self):
        results = {'device_a_test.py': 0, 'device_c_test.py': DEVICE_LOST}
        self.assertIn('device_c_test.py', failures(results))


if __name__ == '__main__':
    unittest.main()
