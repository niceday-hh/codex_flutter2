"""Notification deleteIntent and archive/delete action delivery after process death. No reboot."""
import json
import subprocess
import time
from pathlib import Path
from device_preferences import read_runtime, await_created

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
def adb(*args, check=True):
    p = subprocess.run(['adb', *args], capture_output=True, text=True, timeout=45)
    if check and p.returncode: raise RuntimeError(f'ADB {args}: {p.stdout} {p.stderr}')
    return p.stdout.strip()
def shell(*args, **kwargs): return adb('shell', *args, **kwargs)
def probe(action, *extras): return shell('am','broadcast','--receiver-foreground','-n',RECEIVER,'-a',action,*extras)
def runtime(): return read_runtime(adb, PACKAGE)
def rows(): return json.loads(runtime().get('reminders','[]'))
def wait(predicate, label, timeout=75):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        value=predicate()
        if value: return value
        time.sleep(.5)
    raise AssertionError(label)
def snapshot():
    probe('SNAPSHOT')
    return json.loads(adb('exec-out','run-as',PACKAGE,'cat','files/notification-probe.json'))

result={'reboot_tests_run':False}
original_timeout=shell('settings','get','system','screen_off_timeout')
shell('settings','put','system','screen_off_timeout','600000')
path=Path(f'device-cleanup-test-results-api{shell("getprop","ro.build.version.sdk")}.json')
try:
    shell('input','keyevent','KEYCODE_WAKEUP'); shell('wm','dismiss-keyguard',check=False)
    probe('CLEAR'); probe('CORE_MODE')
    for action,index in [('archive',0),('delete',1)]:
        row=await_created(probe('PRIVACY_SEED'),runtime); id=row['id']
        shell('input','keyevent','KEYCODE_HOME'); probe('REMOVE_TASK'); probe('KILL_PROCESS')
        wait(lambda: not shell('pidof',PACKAGE,check=False),'Process did not exit',12)
        wait(lambda: next((r for r in rows() if r['id']==id and r.get('attempts')==1),None),'Reminder did not fire')
        probe('CLEANUP_DISMISS','--ei','id',str(id))
        wait(lambda: next((r for r in rows() if r['id']==id and r.get('acknowledged') and r.get('retryAt')==0),None),'Dismissal did not acknowledge')
        prompt=wait(lambda: next((n for n in snapshot() if n['id']==-id),None),'Cleanup chooser was not posted',15)
        assert prompt['actionCount']==2 and prompt['importance']==2 and prompt['sound'] is None and not prompt['fullscreen'],prompt
        probe('CLEANUP_ACTION','--ei','id',str(id),'--ei','index',str(index))
        if action=='archive':
            r=wait(lambda: next((r for r in rows() if r['id']==id and r.get('archived')),None),'Archive action did not persist',15)
            assert not r['enabled'] and r['nextTrigger']==0 and r['retryAt']==0
        else: wait(lambda: all(r['id']!=id for r in rows()),'Delete action did not remove task',15)
        result[action+'_after_process_death']=True
    row=await_created(probe('SELF_TEST'),runtime); id=row['id']
    assert row.get('testReminder') and row.get('testAutoDelete'),row
    wait(lambda: next((r for r in rows() if r['id']==id and r.get('attempts')==1),None),'Self-test did not fire')
    probe('CLEANUP_DISMISS','--ei','id',str(id))
    wait(lambda: all(r['id']!=id for r in rows()),'Confirmed self-test was not automatically deleted',15)
    assert all(n['id']!=-id for n in snapshot()),'Self-test must not leave a cleanup chooser'
    result['self_test_auto_deleted']=True
    print('PASS: dismissed notification stops retries; native history/delete and self-test auto-delete persist with UI absent',flush=True)
finally:
    shell('settings','put','system','screen_off_timeout',original_timeout,check=False)
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    if not result.get('self_test_auto_deleted'): print('Cleanup diagnostics:',json.dumps({'runtime':runtime(),'notifications':snapshot()},ensure_ascii=False),flush=True)
    probe('CLEAR')
