import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/extraction_options_dialog.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en', 'de']) {
      testWidgets('creation and extraction options fit $brightness $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(900, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preview = GlobalKey();
        ArchiveCreateOptions? options;
        await tester.pumpWidget(
          RepaintBoundary(
            key: preview,
            child: MaterialApp(
              theme: desktopTheme(brightness: brightness),
              builder: foruiBuilder,
              home: AppLanguageScope(
                languageCode: language,
                child: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () async {
                        options = await showAppDialog<ArchiveCreateOptions>(
                          context: context,
                          builder: (_) => const ArchiveCreateDialog(
                            format: 'zip',
                            aesAvailable: true,
                            initialLevel: 6,
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('split-volumes')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('create-comment')),
          'Package comment ✓',
        );
        expect(find.byKey(const ValueKey('volume-size')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('zip-encryption')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('create-password')),
          'test password',
        );
        await tester.enterText(
          find.byKey(const ValueKey('confirm-password')),
          'test password',
        );
        tester.view.physicalSize = const Size(520, 600);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (language == 'zh') {
          await tester.runAsync(() async {
            final boundary =
                preview.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final screenshot = await boundary.toImage();
            final data = await screenshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/hizip-create-${brightness.name}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            screenshot.dispose();
          });
        }
        await tester.tap(find.text(translateAppText('创建', language)));
        await tester.pumpAndSettle();
        expect(options!.volumeSize, 100 * 1024 * 1024);
        expect(options!.comment, 'Package comment ✓');
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(brightness: brightness),
            builder: foruiBuilder,
            home: AppLanguageScope(
              languageCode: language,
              child: const Center(child: ExtractionOptionsDialog()),
            ),
          ),
        );
        tester.view.physicalSize = const Size(520, 520);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('extraction-conflict-policy')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('extraction dialog returns the selected conflict policy', (
    tester,
  ) async {
    ExtractionConflictPolicy? value;
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async =>
                  value = await showAppDialog<ExtractionConflictPolicy>(
                    context: context,
                    languageCode: 'zh',
                    builder: (_) => const ExtractionOptionsDialog(),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动重命名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('解压'));
    await tester.pumpAndSettle();
    expect(value, ExtractionConflictPolicy.overwrite);
    await tester.pumpWidget(const SizedBox());
  });
}
