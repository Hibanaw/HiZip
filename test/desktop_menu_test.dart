import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/file_context_menu.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('pointer menus stay inside the window at every edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        theme: desktopTheme(),
        home: Scaffold(
          body: FileContextMenu(
            onOpen: () {},
            onCopy: () {},
            onDelete: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    for (final position in [
      const Offset(398, 298),
      const Offset(2, 2),
      const Offset(398, 2),
      const Offset(2, 298),
      const Offset(200, 150),
    ]) {
      await tester.tapAt(position, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final group = find
          .ancestor(of: find.text('打开'), matching: find.byType(FItemGroup))
          .last;
      final bounds = tester.getRect(group);
      expect(bounds.left, greaterThanOrEqualTo(8));
      expect(bounds.top, greaterThanOrEqualTo(8));
      expect(bounds.right, lessThanOrEqualTo(392));
      expect(bounds.bottom, lessThanOrEqualTo(292));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.tapAt(const Offset(2, 2), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(398, 298));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final submenu in [false, true]) {
    testWidgets('long ${submenu ? 'submenus' : 'menus'} fit and scroll', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(180, 220);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = -1;
      final actions = [
        for (var i = 0; i < 24; i++)
          DesktopMenuAction('Action $i', () => selected = i),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          theme: desktopTheme(),
          home: Scaffold(
            body: FileContextMenu(
              actions: submenu
                  ? [DesktopMenuAction('Tools', null, children: actions)]
                  : actions,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.tapAt(
        const Offset(178, 218),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      if (submenu) {
        await tester.tap(find.text('Tools'));
        await tester.pumpAndSettle();
      }
      final group = find
          .ancestor(
            of: find.text('Action 0'),
            matching: find.byType(FItemGroup),
          )
          .evaluate()
          .firstWhere(
            (element) => (element.widget as FItemGroup).maxHeight.isFinite,
          );
      final bounds = tester.getRect(find.byWidget(group.widget));
      expect(bounds.left, greaterThanOrEqualTo(8));
      expect(bounds.top, greaterThanOrEqualTo(8));
      expect(bounds.right, lessThanOrEqualTo(172));
      expect(bounds.bottom, lessThanOrEqualTo(212));
      await tester.scrollUntilVisible(
        find.text('Action 23'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action 23'));
      await tester.pumpAndSettle();
      expect(selected, 23);
      expect(find.text('Action 23'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

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
