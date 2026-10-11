#!/usr/bin/env python3
"""Run the real HAP tests using a VM connection on an unsigned emulator build.

Flutter OH's prebuilt-HAP parser is currently unimplemented. Connect to the
already installed test application instead of modifying SDK signing checks.
"""
import argparse
import pathlib
import re
import socket
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--device', default='127.0.0.1:5555')
parser.add_argument('--skip-build', action='store_true')
args = parser.parse_args()
if not args.skip_build:
    subprocess.run([sys.executable, str(root / 'tools/build-ohos-emulator.py'),
                    '--target', 'integration_test/ohos_archive_test.dart',
                    '--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false'], cwd=root, check=True)
hdc = root / '.toolchains/command-line-tools/sdk/default/openharmony/toolchains/hdc'
command = [str(hdc), '-t', args.device]
hap = root / 'build/ohos/hap/entry-default-unsigned.hap'
subprocess.run([*command, 'install', '-r', str(hap)], check=True)
subprocess.run([*command, 'shell', 'aa', 'force-stop', 'com.hibanaw.hizip'], check=True)
subprocess.run([*command, 'shell', 'hilog', '-r'], check=True, stdout=subprocess.DEVNULL)
launch = subprocess.run([*command, 'shell', 'aa', 'start', '-a', 'EntryAbility',
                         '-b', 'com.hibanaw.hizip'], capture_output=True, text=True, check=True)
print(launch.stdout, end='', flush=True)
if 'start ability successfully' not in launch.stdout:
    sys.exit('The test app did not launch. Check the emulator lock screen and the error above.')
deadline = time.monotonic() + 45
uri = None
while time.monotonic() < deadline:
    log = subprocess.run([*command, 'shell', 'hilog', '-x'], capture_output=True, text=True, timeout=10).stdout
    match = re.search(r'(?:Dart VM service|Observatory).*?(http://127\.0\.0\.1:(\d+)/[^\s]+)', log)
    if match:
        uri, remote_port = match.group(1), match.group(2)
        break
    time.sleep(1)
if uri is None:
    sys.exit('The emulator did not publish a Dart VM service within 45 seconds.')
with socket.socket() as probe:
    probe.bind(('127.0.0.1', 0))
    port = probe.getsockname()[1]
subprocess.run([*command, 'fport', f'tcp:{port}', f'tcp:{remote_port}'], check=True)
host_uri = uri.replace(f':{remote_port}/', f':{port}/')
try:
    result = subprocess.run([str(root / 'tools/flutter-ohos'), 'drive',
                             '--use-existing-app', host_uri, '--no-pub',
                             '--driver', 'test_driver/ohos_integration.dart'], cwd=root)
finally:
    subprocess.run([*command, 'fport', 'rm', f'tcp:{port}', f'tcp:{remote_port}'], check=False)
sys.exit(result.returncode)
