"""Run every device scenario even when another fails; any failure blocks release.

Scenarios kill the app process, force Doze and toggle notifications. On a hosted
runner the emulator occasionally drops its adb transport in the middle of that
sequence, which used to surface as five unrelated tracebacks: every following
script failed on `adb: device offline` instead of on its own assertion. Wait for
a usable device before each scenario, try to bring the transport back once, and
name the scenarios that never got to run.
"""
import os
import subprocess
import sys
import time

SCENARIOS = [
    'device_alarm_test.py',
    'device_speech_test.py',
    'device_cleanup_test.py',
    'device_notification_test.py',
    'device_guardian_test.py',
    'device_popup_test.py',
    'device_entry_test.py',
]
DEVICE_WAIT_SECONDS = int(os.environ.get('MEMO_DEVICE_WAIT_SECONDS', '60'))
DEVICE_LOST = 'device-lost'


def adb(*args, timeout=30):
    return subprocess.run(['adb', *args], capture_output=True, text=True, timeout=timeout)


def device_ready():
    """A device is usable when `wait-for-device` returns and a shell round-trip works."""
    try:
        if adb('wait-for-device', timeout=DEVICE_WAIT_SECONDS).returncode != 0:
            return False
        return adb('shell', 'true').returncode == 0
    except (subprocess.SubprocessError, OSError):
        return False


def ensure_device(script):
    """Reconnect once when the transport went offline; never continue silently without a device."""
    if device_ready():
        return True
    print(f'RECOVER: adb cannot reach the device before {script}; reconnecting', flush=True)
    for args in (('reconnect', 'offline'), ('kill-server',), ('start-server',)):
        try:
            adb(*args)
        except (subprocess.SubprocessError, OSError) as error:
            print(f'RECOVER: adb {" ".join(args)} failed: {error}', flush=True)
    for _ in range(6):
        time.sleep(5)
        if device_ready():
            print(f'RECOVERED: device answers again before {script}', flush=True)
            return True
    return False


def execute(script):
    """Run one scenario as a child process and return its exit code, right or wrong."""
    started = time.monotonic()
    code = subprocess.run([sys.executable, f'tool/{script}'], check=False).returncode
    print(f'{script} finished in {time.monotonic() - started:.0f}s -> {code}', flush=True)
    return code


def run_scenarios(scenarios=None, ensure=ensure_device, execute=execute):
    """Every scenario runs even after a failure; a lost device stops the ones that cannot run."""
    scenarios = SCENARIOS if scenarios is None else scenarios
    results = {}
    for index, script in enumerate(scenarios):
        if not ensure(script):
            for skipped in scenarios[index:]:
                results[skipped] = DEVICE_LOST
            print(f'LOST: device gone before {script}; remaining scenarios did not run', flush=True)
            break
        results[script] = execute(script)
    return results


def failures(results):
    """A scenario that never ran is a failure, not a pass."""
    return {script: code for script, code in results.items() if code != 0}


def main():
    results = run_scenarios()
    print('Device scenario exit codes:', results, flush=True)
    return 1 if failures(results) else 0


if __name__ == '__main__':
    sys.exit(main())
