import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/ui/file_context_menu.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
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
