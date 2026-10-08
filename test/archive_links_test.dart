import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service_io.dart';
import 'package:hizip/ui/breathing_status_bar.dart';
import 'package:path/path.dart' as p;

void main() {
  caseTests();
  test('link targets leaving the extraction folder are unsafe', () {
    expect(isUnsafeLinkTarget('a/b', '/etc/passwd'), isTrue);
    expect(isUnsafeLinkTarget('a/b', 'C:\\Windows'), isTrue);
    expect(isUnsafeLinkTarget('a/b', '../../x'), isTrue);
    expect(isUnsafeLinkTarget('b', '../x'), isTrue);
    expect(isUnsafeLinkTarget('a/b', ''), isTrue);
    expect(isUnsafeLinkTarget('a/b', '../c'), isFalse);
    expect(isUnsafeLinkTarget('a/b/c', '../../d/e'), isFalse);
    expect(isUnsafeLinkTarget('a/b', './c/../d'), isFalse);
  });

  testWidgets('status bar pulses only while active and reports taps', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    var taps = 0;
    Widget bar(bool active) => MaterialApp(
      home: BreathingStatusBar(
        active: active,
        tint: Colors.red,
        height: 30,
        padding: EdgeInsets.zero,
        decoration: const BoxDecoration(color: Colors.white),
        onTap: () => taps++,
        child: const SizedBox.expand(),
      ),
    );
    Color? color() =>
        (tester.widget<Container>(find.byType(Container).first).decoration
                as BoxDecoration)
            .color;
    await tester.pumpWidget(bar(true));
    await tester.pump(const Duration(milliseconds: 700));
    expect(color(), isNot(Colors.white));
    await tester.tap(find.byType(BreathingStatusBar));
    expect(taps, 1);
    await tester.pumpWidget(bar(false));
    await tester.pumpAndSettle();
    expect(color(), Colors.white);
    await tester.tap(find.byType(BreathingStatusBar));
    expect(taps, 1);
  });

  final enabled = Platform.environment['HIZIP_NATIVE_LIBRARY'] != null;
  test('unsafe links honour the chosen policy', () async {
    final root = await Directory.systemTemp.createTemp('hizip-links-');
    final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
    try {
      final src = Directory(p.join(root.path, 'src', 'lib'))
        ..createSync(recursive: true);
      File(p.join(src.path, 'real.txt')).writeAsStringSync('hi');
      Link(p.join(root.path, 'src', 'ok')).createSync('lib/real.txt');
      Link(p.join(root.path, 'src', 'abs')).createSync('/etc/passwd');
      final tar = p.join(root.path, 'a.tar');
      final made = await Process.run('tar', [
        'cf',
        tar,
        '-C',
        root.path,
        'src',
      ]);
      expect(made.exitCode, 0);
      final doc = await service.read(tar);
      expect(doc.entries.where((e) => e.hasUnsafeLink).map((e) => e.path), [
        'src/abs',
      ]);
      final kept = Directory(p.join(root.path, 'keep'))..createSync();
      final keptRoot = await service.extract(doc, kept.path);
      expect(Link(p.join(keptRoot, 'src', 'abs')).existsSync(), isTrue);
      final skipped = Directory(p.join(root.path, 'skip'))..createSync();
      final skippedRoot = await service.extract(
        doc,
        skipped.path,
        linkPolicy: LinkPolicy.skipUnsafe,
      );
      expect(Link(p.join(skippedRoot, 'src', 'abs')).existsSync(), isFalse);
      expect(
        Link(p.join(skippedRoot, 'src', 'ok')).targetSync(),
        'lib/real.txt',
      );
    } finally {
      await service.dispose();
      await root.delete(recursive: true);
    }
  }, skip: enabled ? false : 'HIZIP_NATIVE_LIBRARY is not set');
}

void caseTests() {
  final enabled = Platform.environment['HIZIP_NATIVE_LIBRARY'] != null;
  for (final policy in CaseConflictPolicy.values) {
    test('case-only name clashes are resolved by $policy', () async {
      final root = await Directory.systemTemp.createTemp('hizip-case-');
      final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
      debugForceCaseInsensitive = true;
      try {
        final src = Directory(p.join(root.path, 'src'))..createSync();
        File(p.join(src.path, 'ipt_ECN.h')).writeAsStringSync('upper');
        File(p.join(src.path, 'ipt_ecn.h')).writeAsStringSync('lower');
        final tar = p.join(root.path, 'c.tar');
        expect(
          (await Process.run('tar', [
            'cf',
            tar,
            '-C',
            root.path,
            'src',
          ])).exitCode,
          0,
        );
        final doc = await service.read(tar);
        final out = Directory(p.join(root.path, 'out'))..createSync();
        expect(await service.caseConflicts(doc, out.path), hasLength(1));
        final notices = <String>[];
        final dest = await service.extract(
          doc,
          out.path,
          caseConflictPolicy: policy,
          notice: notices.add,
        );
        final names = Directory(p.join(dest, 'src'))
            .listSync()
            .map((e) => p.basename(e.path))
            .toSet();
        if (policy == CaseConflictPolicy.rename) {
          expect(names.length, 2);
          expect(names.any((n) => n.contains('(2)')), isTrue);
        } else {
          expect(names.length, 1);
        }
        expect(notices, hasLength(1));
        debugForceCaseInsensitive = false;
        expect(await service.caseConflicts(doc, out.path), isEmpty);
      } finally {
        debugForceCaseInsensitive = null;
        await service.dispose();
        await root.delete(recursive: true);
      }
    }, skip: enabled ? false : 'HIZIP_NATIVE_LIBRARY is not set');
  }
}
