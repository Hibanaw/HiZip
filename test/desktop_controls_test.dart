import 'package:flutter/material.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/models/theme_accent.dart';

void main() {
  testWidgets('hover previews the accent and clears when the pointer leaves', (
    tester,
  ) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    Color background() => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('candidate')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .first
        .color!;
    for (final brightness in Brightness.values) {
      for (final accent in ThemeAccent.values) {
        for (final flat in [true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: desktopTheme(brightness: brightness, accent: accent),
              builder: foruiBuilder,
              home: Scaffold(
                body: Center(
                  child: DesktopButton(
                    key: const ValueKey('candidate'),
                    flat: flat,
                    onPressed: () {},
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.settings), Text('Appearance')],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final normal = background();
          final button = find.byKey(const ValueKey('candidate'));
          await mouse.moveTo(tester.getCenter(button));
          await tester.pumpAndSettle();
          final hover = background();
          expect(hover, isNot(normal));
          expect(hover.a, inExclusiveRange(0, .25));
          expect(hover.withValues(alpha: 1), accent.color);
          final context = tester.element(find.text('Appearance'));
          final foreground = DefaultTextStyle.of(context).style.color;
          final hoverSurface = Color.alphaBlend(
            hover,
            FTheme.of(context).colors.card,
          );
          expect(
            foreground,
            desktopAccentForeground(context, background: hoverSurface),
          );
          final foregroundLuminance = foreground!.computeLuminance() + .05;
          final backgroundLuminance = hoverSurface.computeLuminance() + .05;
          expect(
            foregroundLuminance > backgroundLuminance
                ? foregroundLuminance / backgroundLuminance
                : backgroundLuminance / foregroundLuminance,
            greaterThanOrEqualTo(4.5),
          );
          expect(
            IconTheme.of(tester.element(find.byIcon(Icons.settings))).color,
            foreground,
          );
          await mouse.moveTo(const Offset(700, 500));
          await tester.pumpAndSettle();
          expect(background(), normal);
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

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
