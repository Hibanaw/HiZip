#!/usr/bin/env python3
"""Apply the two OH enum fallbacks to an isolated, reproducible ForUI copy."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
target = root / '.toolchains/forui-ohos'
override = root / 'pubspec_overrides.yaml'
if target.exists():
    override.write_text('dependency_overrides:\n  forui:\n    path: .toolchains/forui-ohos\n')
    raise SystemExit(0)
source = root / '.toolchains/pub-cache/hosted/pub.flutter-io.cn/forui-0.21.3'
if not source.is_dir():
    raise SystemExit('ForUI 0.21.3 is missing; run tools/flutter-ohos pub get.')
patches = {
    'lib/src/foundation/barrier.dart': ('.fuchsia || .linux || .windows => false,', '.fuchsia || .linux || .windows => false,\n          _ => true,'),
    'lib/src/theme/adaptive_scope.dart': ('.linux => .linux,', '.linux => .linux,\n      _ => .android,'),
}
# Fail rather than silently patching a changed upstream release.
for name, (before, _) in patches.items():
    if (source / name).read_text().count(before) != 1:
        raise SystemExit(f'Unexpected ForUI source: {name}')
target.mkdir(parents=True)
for name in ('lib', 'assets'):
    shutil.copytree(source / name, target / name)
for name in ('LICENSE', 'pubspec.yaml'):
    shutil.copy2(source / name, target / name)
manifest = (target / 'pubspec.yaml').read_text().replace('resolution: workspace\nworkspace:\n  - example\n', '')
(target / 'pubspec.yaml').write_text(manifest)
for name, (before, after) in patches.items():
    path = target / name
    path.write_text(path.read_text().replace(before, after))
override.write_text('dependency_overrides:\n  forui:\n    path: .toolchains/forui-ohos\n')
print('Prepared isolated ForUI 0.21.3 with HarmonyOS touch fallbacks.')
