import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Forui select supports keyboard and dismisses in $brightness', (
      tester,
    ) async {
      var value = 'auto';
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness: brightness),
          builder: foruiBuilder,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: StatefulBuilder(
                  builder: (context, setState) => DesktopSelect<String>(
                    items: const {'自动识别': 'auto', 'UTF-8': 'UTF-8'},
                    value: value,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DesktopSelect<String>));
      await tester.pumpAndSettle();
      expect(find.text('UTF-8'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('UTF-8'), findsNothing);
      expect(value, 'auto');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('UTF-8'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, 'UTF-8');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Forui slider uses numeric keyboard steps and integer compression levels',
    (tester) async {
      var value = 6.0;
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: StatefulBuilder(
                  builder: (context, setState) => DesktopSlider(
                    value: value,
                    min: 0,
                    max: 9,
                    divisions: 9,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(value, 7);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(value, 6);
      expect(find.byType(FSlider), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
