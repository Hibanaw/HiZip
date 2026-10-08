import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/window_close_button.dart';
import 'package:libadwaita/libadwaita.dart' as adw;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Linux close button uses Adwaita in $brightness', (
      tester,
    ) async {
      var closeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness: brightness),
          builder: foruiBuilder,
          home: Scaffold(
            body: Center(
              child: WindowCloseButton(
                platform: TargetPlatform.linux,
                onPressed: () => closeCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<adw.AdwWindowButton>(
        find.byType(adw.AdwWindowButton),
      );
      expect(button.buttonType, adw.WindowButtonType.close);
      expect(button.nativeControls, isFalse);
      expect(
        tester.widget<adw.AdwButton>(find.byType(adw.AdwButton)).shape,
        BoxShape.circle,
      );
      expect(find.byType(DesktopIconButton), findsNothing);
      expect(
        tester.getSize(find.byType(adw.AdwWindowButton)),
        const Size(36, 36),
      );
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, '关闭');
      await tester.tap(find.byType(adw.AdwWindowButton));
      expect(closeCount, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(closeCount, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(closeCount, 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Other platforms keep the existing close button', (tester) async {
    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      var closeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: Scaffold(
            body: WindowCloseButton(
              platform: platform,
              onPressed: () => closeCount++,
            ),
          ),
        ),
      );
      expect(find.byType(adw.AdwWindowButton), findsNothing);
      expect(find.byType(DesktopIconButton), findsOneWidget);
      await tester.tap(find.byType(DesktopIconButton));
      await tester.pumpAndSettle();
      expect(closeCount, 1);
      expect(tester.takeException(), isNull);
    }
  });
}
