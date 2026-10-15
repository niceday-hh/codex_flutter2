import subprocess
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import Mock, patch
from device_preferences import read_runtime, await_created

PACKAGE = 'debug.app'
PATH = f'/data/user_de/0/{PACKAGE}/shared_prefs/memo-runtime.xml'
VALID = '<map><string name="reminders">[{&quot;id&quot;:7}]</string><boolean name="reliableMode" value="true"/></map>'


def reader(values, backup=False):
    values = iter(values)
    def read(*args, **kwargs):
        if args[3] == 'ls':
            return PATH + '.bak' if backup else ''
        value = next(values)
        if isinstance(value, Exception):
            raise value
        return value
    return Mock(side_effect=read)


class RuntimeReadTest(unittest.TestCase):
    @patch('device_preferences.time.sleep')
    def test_partial_or_replaced_file_then_complete_snapshot(self, sleep):
        adb = reader(['', '<map><string name="reminders">',
                      subprocess.CalledProcessError(1, ['cat']), VALID])
        self.assertEqual(read_runtime(adb, PACKAGE, attempts=4),
                         {'reminders': '[{"id":7}]', 'reliableMode': 'true'})
        self.assertEqual(sleep.call_count, 3)
        self.assertEqual(adb.call_args.args, ('exec-out', 'run-as', PACKAGE, 'cat', PATH))

    @patch('device_preferences.time.sleep')
    def test_permanently_broken_file_is_not_reported_as_empty_state(self, sleep):
        adb = reader(['<map>'] * 3)
        with self.assertRaises(ET.ParseError):
            read_runtime(adb, PACKAGE, attempts=3)
        self.assertEqual(sleep.call_count, 2)

    @patch('device_preferences.time.sleep')
    def test_persistent_transport_error_still_fails(self, sleep):
        adb = reader([subprocess.CalledProcessError(1, ['cat'])] * 3)
        with self.assertRaises(subprocess.CalledProcessError):
            read_runtime(adb, PACKAGE, attempts=3)
        self.assertEqual(sleep.call_count, 2)

    def test_committed_backup_is_read_without_launching_or_mutating_app(self):
        adb = reader([VALID], backup=True)
        self.assertEqual(read_runtime(adb, PACKAGE)['reminders'], '[{"id":7}]')
        self.assertEqual(adb.call_args.args, ('exec-out', 'run-as', PACKAGE, 'cat', PATH + '.bak'))
        self.assertEqual([c.args[3] for c in adb.call_args_list], ['ls', 'cat'])

    @patch('device_preferences.time.sleep')
    def test_corrupt_backup_does_not_silently_fall_back_to_uncommitted_main(self, sleep):
        adb = reader([''] * 3, backup=True)
        with self.assertRaises(ET.ParseError):
            read_runtime(adb, PACKAGE, attempts=3)
        self.assertTrue(all(c.args[4].endswith('.bak') for c in adb.call_args_list))


class CreatedReminderTest(unittest.TestCase):
    @patch('device_preferences.time.sleep')
    def test_waits_for_broadcast_returned_id_instead_of_using_old_last_row(self, sleep):
        snapshot = Mock(side_effect=[{'reminders': '[]'},
            {'reminders': '[{"id":4,"nextTrigger":10}]'},
            {'reminders': '[{"id":4,"nextTrigger":10},{"id":7,"nextTrigger":20}]'}])
        self.assertEqual(await_created('Broadcast completed: result=7', snapshot), {'id': 7, 'nextTrigger': 20})
        self.assertEqual(snapshot.call_count, 3)

    def test_failed_broadcast_does_not_select_an_existing_task(self):
        snapshot = Mock()
        with self.assertRaises(AssertionError):
            await_created('Broadcast completed: result=0', snapshot)
        snapshot.assert_not_called()

    @patch('device_preferences.time.sleep')
    @patch('device_preferences.time.monotonic', side_effect=[0, 0, 2])
    def test_unobserved_fixture_id_still_fails(self, clock, sleep):
        with self.assertRaises(AssertionError):
            await_created('Broadcast completed: result=7', lambda: {'reminders': '[]'}, timeout=1)


if __name__ == '__main__':
    unittest.main()
