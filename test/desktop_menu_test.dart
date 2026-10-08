import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/file_context_menu.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
  testWidgets('archive open-with menu prioritizes HiZip', (tester) async {
    var openedInHiZip = false;
    FileApplication? openedApplication;
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        theme: desktopTheme(),
        home: Scaffold(
          body: FileContextMenu(
            applicationOnly: true,
            primaryClick: true,
            onOpenInHiZip: () => openedInHiZip = true,
            applications: () async => const [
              FileApplication(
                'Archive Viewer',
                null,
                '/viewer',
                isDefault: true,
              ),
              FileApplication('Other Viewer', null, '/other'),
            ],
            onOpenWith: (app) => openedApplication = app,
            onChooseApplication: () {},
            child: const SizedBox(
              key: ValueKey('archive-open-with'),
              width: 80,
              height: 40,
              child: Text('archive'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-open-with')));
    await tester.pumpAndSettle();
    expect(find.text('在 HiZip 中打开'), findsOneWidget);
    expect(find.text('其他应用'), findsOneWidget);
    expect(find.text('Archive Viewer（默认）'), findsNothing);
    await tester.tap(find.text('其他应用'));
    await tester.pumpAndSettle();
    expect(find.text('Archive Viewer（默认）'), findsOneWidget);
    expect(find.text('Other Viewer'), findsOneWidget);
    expect(find.text('其他…'), findsOneWidget);
    await tester.tap(find.text('Archive Viewer（默认）'));
    await tester.pumpAndSettle();
    expect(openedApplication?.path, '/viewer');
    expect(openedInHiZip, isFalse);
    await tester.tap(find.byKey(const ValueKey('archive-open-with')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在 HiZip 中打开'));
    await tester.pumpAndSettle();
    expect(openedInHiZip, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'custom menu supports keyboard, dismissal and screen bounds without Material menus',
    (tester) async {
      var copies = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          theme: desktopTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: FileContextMenu(
                onOpen: () {},
                onCopy: () => copies++,
                onPaste: null,
                child: const SizedBox(
                  key: ValueKey('target'),
                  width: 80,
                  height: 40,
                  child: Text('file'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.byType(SubmenuButton), findsNothing);
      final copyBounds = tester.getRect(find.text('复制'));
      expect(
        copyBounds.right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(copies, 1);
      expect(find.text('复制'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('target')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
