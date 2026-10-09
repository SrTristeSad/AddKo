#!/usr/bin/env python3
"""Require a Flutter frame, ready Kodi RPC, and a stable native process."""
from pathlib import Path
import subprocess
import sys
import time

OUTPUT = Path('dist/startup')
OUTPUT.mkdir(parents=True, exist_ok=True)
PACKAGE = 'com.srtristesad.addko'
LOG_FILTERS = ['AddKo:I', 'Kodi:I', 'libc:F', 'DEBUG:F', 'AndroidRuntime:E', 'flutter:I', '*:S']
stream = None
stream_file = None


def adb(*args, check=True):
    r = subprocess.run(['adb', *args], capture_output=True, text=True, timeout=45)
    if check and r.returncode:
        raise RuntimeError('adb ' + ' '.join(args) + ': exit ' + str(r.returncode) + '\n' + r.stdout + r.stderr)
    return r.stdout + r.stderr


try:
    abis = adb('shell', 'getprop', 'ro.product.cpu.abilist')
    if 'arm64-v8a' not in abis:
        raise RuntimeError('Test device cannot execute ARM64 Kodi: ' + abis)
    adb('install', '-r', sys.argv[1])
    adb('logcat', '-G', '16M', check=False)
    adb('logcat', '-c')
    stream_file = (OUTPUT / 'startup-stream.txt').open('w')
    stream = subprocess.Popen(['adb', 'logcat', '-v', 'threadtime', '-s', *LOG_FILTERS], stdout=stream_file, stderr=stream_file)
    (OUTPUT / 'launch.txt').write_text(adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity'))
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        logs = (OUTPUT / 'startup-stream.txt').read_text(errors='replace')
        if stream.poll() is not None:
            stream = subprocess.Popen(['adb', 'logcat', '-v', 'threadtime', '-s', *LOG_FILTERS], stdout=stream_file, stderr=stream_file)
        if ('>>> com.srtristesad.addko:kodi <<<' in logs or
                ('JNI DETECTED ERROR IN APPLICATION' in logs and 'com.srtristesad.addko' in logs)):
            raise RuntimeError('Native Kodi crashed during startup; see collected logcat')
        if 'Flutter first frame displayed' in logs and 'Kodi JSON-RPC ready' in logs:
            break
        time.sleep(3)
    else:
        raise RuntimeError('No Flutter frame and ready Kodi RPC within 180 seconds')
    first_pid = adb('shell', 'pidof', PACKAGE + ':kodi').strip()
    if not first_pid:
        raise RuntimeError('Native core process is not alive')
    time.sleep(15)
    if adb('shell', 'pidof', PACKAGE + ':kodi').strip() != first_pid:
        raise RuntimeError('Native core exited or restarted after first frame')
    adb('shell', 'uiautomator', 'dump', '/sdcard/addko-ui.xml')
    adb('pull', '/sdcard/addko-ui.xml', str(OUTPUT / 'ui.xml'))
    with (OUTPUT / 'screen.png').open('wb') as out:
        subprocess.run(['adb', 'exec-out', 'screencap', '-p'], stdout=out, check=True, timeout=45)
    print('PASS: Flutter frame, Kodi RPC ready, native process survived 15s.')
finally:
    if stream is not None:
        stream.terminate()
        stream.wait(timeout=10)
    if stream_file is not None:
        stream_file.close()
    for name, args in {
        'logcat.txt': ('logcat', '-d', '-v', 'threadtime'),
        'activity.txt': ('shell', 'dumpsys', 'activity', 'activities'),
        'exit-info.txt': ('shell', 'dumpsys', 'activity', 'exit-info', PACKAGE),
        'device.txt': ('shell', 'getprop'),
    }.items():
        (OUTPUT / name).write_text(adb(*args, check=False))
