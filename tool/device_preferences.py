"""Read only debug runtime XML, tolerating an in-progress SharedPreferences disk write."""
import subprocess
import time
import xml.etree.ElementTree as ET


def read_runtime(adb, package, attempts=20):
    for attempt in range(attempts):
        try:
            path = f'/data/user_de/0/{package}/shared_prefs/memo-runtime.xml'
            # Android loadFromDisk prefers .bak after a process dies mid-write.
            # Read it without restarting the stopped app or altering either file.
            backup = adb('exec-out', 'run-as', package, 'ls', path + '.bak', check=False)
            selected = path + '.bak' if backup.strip() == path + '.bak' else path
            source = adb('exec-out', 'run-as', package, 'cat', selected)
            root = ET.fromstring(source)
            if root.tag != 'map':
                raise ET.ParseError('Expected SharedPreferences map')
            return {e.attrib['name']: e.text if e.tag == 'string' else e.attrib.get('value') for e in root}
        except (ET.ParseError, subprocess.SubprocessError):
            if attempt + 1 == attempts:
                raise
            time.sleep(0.1)
    raise ValueError('attempts must be positive')
