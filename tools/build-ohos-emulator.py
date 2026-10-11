#!/usr/bin/env python3
"""Build an unsigned emulator HAP without changing local signing credentials."""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
profile = root / 'ohos/build-profile.json5'
original = profile.read_bytes() if profile.exists() else None
try:
    profile.write_bytes((root / 'ohos/build-profile.template.json5').read_bytes())
    result = subprocess.run([str(root / 'tools/flutter-ohos'), 'build', 'hap',
                             '--debug', '--no-pub', '--no-codesign', *sys.argv[1:]], cwd=root)
finally:
    if original is None:
        profile.unlink(missing_ok=True)
    else:
        profile.write_bytes(original)
sys.exit(result.returncode)
