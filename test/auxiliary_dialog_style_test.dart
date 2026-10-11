import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/archive_properties.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/inline_properties_dialog.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'inline dialogs are centered and share ${brightness.name} surfaces',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettings(
          read: () async => null,
          write: (_) async {},
        );
        addTearDown(settings.dispose);
        final data = archivePropertiesSnapshot(
          ArchiveDocument(
            '/sample.zip',
            const [],
            'ZIP',
            true,
            comment: 'Notes',
          ),
          '',
          [],
        );
        Future<void> mount(Widget child) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: desktopTheme(brightness: brightness),
              builder: foruiBuilder,
              home: child,
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(
          InlinePropertiesDialog(
            settings: settings,
            data: data,
            onAction: (_, _) async => data,
          ),
        );
        final panel = find.byKey(const ValueKey('properties-panel'));
        final context = tester.element(panel);
        final colors = FTheme.of(context).colors;
        expect(tester.getCenter(panel).dx, closeTo(600, .1));
        expect(
          (tester.widget<Container>(panel).decoration as BoxDecoration).color,
          colors.card,
        );
        expect(
          tester
              .widget<Scaffold>(
                find.byKey(const ValueKey('properties-window-page')),
              )
              .backgroundColor,
          colors.card,
        );
        await tester.tap(find.byKey(const ValueKey('archive-comment-edit')));
        await tester.pumpAndSettle();
        final propertyInput = tester.widget<DesktopTextField>(
          find.byKey(const ValueKey('archive-comment-input')),
        );
        final inputSize = propertyInput.fontSize;
        final inputPadding = propertyInput.contentPadding;
        expect(tester.takeException(), isNull);

        await mount(
          ArchiveCreateDialog(
            format: 'zip',
            aesAvailable: true,
            initialLevel: 6,
            formats: const {'zip': 'ZIP'},
            initialPaths: ['/sample.txt'],
            initialOutputPath: '/sample.zip',
            onSelectionConfirmed: (_, _) {},
          ),
        );
        final contents = find.byKey(const ValueKey('create-contents'));
        expect(tester.getCenter(contents).dx, closeTo(600, .1));
        final border =
            (tester.widget<Container>(contents).decoration as BoxDecoration)
                    .border!
                as Border;
        expect(
          border.top.color,
          FTheme.of(tester.element(contents)).colors.border,
        );
        final createInput = tester.widget<DesktopTextField>(
          find.byKey(const ValueKey('create-comment')),
        );
        expect(createInput.fontSize, inputSize);
        expect(createInput.contentPadding, inputPadding);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
