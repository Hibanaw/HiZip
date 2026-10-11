import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/theme_accent.dart';
import 'package:hizip/models/selection_highlight.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
  double contrast(Color a, Color b) {
    final x = a.computeLuminance() + .05;
    final y = b.computeLuminance() + .05;
    return x > y ? x / y : y / x;
  }

  Color buttonBackground(WidgetTester tester, Finder button) => tester
      .widgetList<DecoratedBox>(
        find.descendant(of: button, matching: find.byType(DecoratedBox)),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.color)
      .whereType<Color>()
      .first;

  testWidgets(
    'reference accent fills use white content in both themes and hover',
    (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      addTearDown(mouse.removePointer);
      for (final brightness in Brightness.values) {
        for (final accent in ThemeAccent.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: desktopTheme(brightness: brightness, accent: accent),
              builder: foruiBuilder,
              home: Scaffold(
                body: Row(
                  children: [
                    DesktopButton(
                      key: const ValueKey('action'),
                      primary: true,
                      onPressed: () {},
                      child: const Text('action'),
                    ),
                    const SizedBox(width: 20),
                    DesktopButton(
                      key: const ValueKey('choice'),
                      active: true,
                      onPressed: () {},
                      child: const Text('choice'),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.text('action'));
          final colors = FTheme.of(context).colors;
          final scheme = Theme.of(context).colorScheme;
          expect(colors.primaryForeground, scheme.onPrimary);
          expect(scheme.onPrimary, Colors.white);
          expect(scheme.primaryContainer, scheme.primary);
          expect(scheme.onPrimaryContainer, scheme.onPrimary);
          expect(
            contrast(desktopAccentForeground(context), scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          for (final secondary in [false, true]) {
            expect(
              fileSelectionForeground(
                context,
                SelectionHighlight.blue,
                secondary: secondary,
              ),
              scheme.onPrimary,
            );
          }
          for (final role in ['action', 'choice']) {
            final button = find.byKey(ValueKey(role));
            final foreground = DefaultTextStyle.of(
              tester.element(find.text(role)),
            ).style.color!;
            final normal = buttonBackground(tester, button);
            expect(foreground, scheme.onPrimary);
            expect(
              normal,
              role == 'action' ? scheme.primary : scheme.primaryContainer,
            );
            expect(normal.a, 1);
            await mouse.moveTo(tester.getCenter(button));
            await tester.pumpAndSettle();
            final hovered = buttonBackground(tester, button);
            expect(
              DefaultTextStyle.of(tester.element(find.text(role))).style.color,
              Colors.white,
            );
            expect(hovered, isNot(normal));
            expect(hovered.a, 1);
            await mouse.moveTo(const Offset(700, 500));
            await tester.pumpAndSettle();
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('theme accent defaults to orange and preserves saved choices', () async {
    String? stored;
    AppSettings create() => AppSettings(
      read: () async => null,
      readAccent: () async => stored,
      writeAccent: (value) async => stored = value,
    );
    final first = create();
    final second = create();
    expect(first.accent, ThemeAccent.orange);
    await first.load();
    expect(first.accent, ThemeAccent.orange);
    expect(desktopTheme().colorScheme.primary, ThemeAccent.orange.color);
    await first.setAccent(ThemeAccent.green);
    await second.load();
    expect(second.accent, ThemeAccent.green);
    stored = 'invalid';
    await second.load();
    expect(second.accent, ThemeAccent.orange);
    stored = 'blue';
    await second.load();
    expect(second.accent, ThemeAccent.blue);
    first.dispose();
    second.dispose();
  });

  test('legacy teal preference migrates consistently across windows', () async {
    final settings = AppSettings(readAccent: () async => 'teal');
    await settings.load();
    expect(settings.accent, ThemeAccent.green);
    settings.synchronizeAccent('blue');
    settings.synchronizeAccent('teal');
    expect(settings.accent, ThemeAccent.green);
    settings.dispose();
  });

  test('failed accent save retains current color', () async {
    final settings = AppSettings(
      writeAccent: (_) async => throw StateError('disk'),
    );
    await settings.setAccent(ThemeAccent.rose);
    expect(settings.accent, ThemeAccent.orange);
    expect(settings.error, isNotNull);
    settings.dispose();
  });

  test('loading accent notifies even when another preference fails', () async {
    final settings = AppSettings(
      read: () async => throw StateError('disk'),
      readAccent: () async => 'teal',
    );
    var notifications = 0;
    settings.addListener(() => notifications++);
    await settings.load();
    expect(settings.accent, ThemeAccent.green);
    expect(notifications, 1);
    settings.dispose();
  });

  for (final accent in ThemeAccent.values) {
    for (final brightness in Brightness.values) {
      test('${accent.name} uses white foreground in $brightness', () {
        final theme = desktopTheme(brightness: brightness, accent: accent);
        expect(theme.colorScheme.onPrimary, Colors.white);
        expect(theme.colorScheme.primary, accent.colorFor(brightness));
        expect(
          theme.checkboxTheme.checkColor!.resolve({WidgetState.selected}),
          theme.colorScheme.onPrimary,
        );
        if (brightness == Brightness.light) {
          expect(theme.colorScheme.primaryContainer, theme.colorScheme.primary);
          expect(
            theme.colorScheme.onPrimaryContainer,
            theme.colorScheme.onPrimary,
          );
        }
      });
    }
  }
}
