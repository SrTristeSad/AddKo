#!/usr/bin/env python3
"""Verify that Flutter survives independently and Kodi starts in :kodi."""
from pathlib import Path
import subprocess
import sys
import time

OUTPUT = Path('dist/startup')
OUTPUT.mkdir(parents=True, exist_ok=True)
PACKAGE = 'com.srtristesad.addko'
LOG_FILTERS = [
    'AddKo:I',
    'AddKoLegacy:I',
    'Kodi:I',
    'libc:F',
    'DEBUG:F',
    'AndroidRuntime:E',
    'flutter:I',
    '*:S',
]
stream = None
stream_file = None


def adb(*args, check=True):
    r = subprocess.run(['adb', *args], capture_output=True, text=True, timeout=45)
    if check and r.returncode:
        raise RuntimeError(
            'adb ' + ' '.join(args) + ': exit ' + str(r.returncode) + '\n' + r.stdout + r.stderr
        )
    return r.stdout + r.stderr


def logs():
    if stream_file is not None:
        stream_file.flush()
    return (OUTPUT / 'startup-stream.txt').read_text(errors='replace')


try:
    abis = adb('shell', 'getprop', 'ro.product.cpu.abilist')
    if 'arm64-v8a' not in abis:
        raise RuntimeError('Test device cannot execute ARM64 Kodi: ' + abis)

    adb('install', '-r', sys.argv[1])
    adb(
        'shell',
        'settings',
        'put',
        'secure',
        'immersive_mode_confirmations',
        'confirmed',
        check=False,
    )
    adb('logcat', '-G', '16M', check=False)
    adb('logcat', '-c')

    stream_file = (OUTPUT / 'startup-stream.txt').open('w')
    stream = subprocess.Popen(
        ['adb', 'logcat', '-v', 'threadtime', '-s', *LOG_FILTERS],
        stdout=stream_file,
        stderr=stream_file,
    )

    # 1) The normal app must start as a FlutterActivity with no Kodi process.
    (OUTPUT / 'launch.txt').write_text(
        adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')
    )
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        current = logs()
        if 'Flutter launcher channel ready' in current:
            break
        if 'FATAL EXCEPTION' in current and PACKAGE in current:
            raise RuntimeError('Flutter launcher crashed; see collected logcat')
        time.sleep(2)
    else:
        raise RuntimeError('Flutter launcher did not become ready within 90 seconds')

    flutter_pid = adb('shell', 'pidof', PACKAGE).strip()
    if not flutter_pid:
        raise RuntimeError('Flutter process is not alive')
    if adb('shell', 'pidof', PACKAGE + ':kodi', check=False).strip():
        raise RuntimeError('Kodi started during normal Flutter launch; isolation regressed')

    # 2) Ask the exported launcher to trigger the internal isolated Kodi smoke test.
    adb(
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        PACKAGE + '/.MainActivity',
        '--ez',
        'addko.ci_self_test',
        'true',
    )

    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        current = logs()
        if (
            '>>> com.srtristesad.addko:kodi <<<' in current
            or ('JNI DETECTED ERROR IN APPLICATION' in current and PACKAGE in current)
        ):
            raise RuntimeError('Native Kodi crashed during startup; see collected logcat')
        if 'Kodi JSON-RPC pronto' in current:
            break
        time.sleep(3)
    else:
        raise RuntimeError('Isolated Kodi JSON-RPC did not become ready within 180 seconds')

    kodi_pid = adb('shell', 'pidof', PACKAGE + ':kodi').strip()
    if not kodi_pid:
        raise RuntimeError('Isolated Kodi process is not alive')

    # The important regression check: starting Kodi must not replace/kill Flutter.
    if adb('shell', 'pidof', PACKAGE).strip() != flutter_pid:
        raise RuntimeError('Flutter process exited or restarted after isolated Kodi launch')

    time.sleep(15)
    if adb('shell', 'pidof', PACKAGE + ':kodi').strip() != kodi_pid:
        raise RuntimeError('Native Kodi exited or restarted during the stability window')
    if adb('shell', 'pidof', PACKAGE).strip() != flutter_pid:
        raise RuntimeError('Flutter process did not survive the Kodi stability window')

    adb('shell', 'uiautomator', 'dump', '/sdcard/addko-ui.xml', check=False)
    adb('pull', '/sdcard/addko-ui.xml', str(OUTPUT / 'ui.xml'), check=False)
    with (OUTPUT / 'screen.png').open('wb') as out:
        subprocess.run(
            ['adb', 'exec-out', 'screencap', '-p'],
            stdout=out,
            check=True,
            timeout=45,
        )

    print('PASS: Flutter stayed alive; isolated Kodi JSON-RPC started and survived 15s.')
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
