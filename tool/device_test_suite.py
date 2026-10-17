"""Run every device scenario even when another fails; any failure blocks release."""
import subprocess
import sys

results = {}
for script in ['device_alarm_test.py', 'device_speech_test.py', 'device_cleanup_test.py', 'device_notification_test.py', 'device_guardian_test.py', 'device_popup_test.py']:
    results[script] = subprocess.run([sys.executable, f'tool/{script}'], check=False).returncode
print('Device scenario exit codes:', results, flush=True)
sys.exit(1 if any(results.values()) else 0)
