import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/theme_accent.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/settings_page.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance() + .05;
  final y = b.computeLuminance() + .05;
  return x > y ? x / y : y / x;
}

Color decorationColor(Decoration decoration) => switch (decoration) {
  BoxDecoration(:final color) => color!,
  ShapeDecoration(:final color) => color!,
  _ => throw StateError('Unsupported decoration'),
};

void main() {
  testWidgets('selected theme swatch uses white checkmark and text', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final accent in [ThemeAccent.orange, ThemeAccent.yellow]) {
        final settings = AppSettings(writeAccent: (_) async {});
        await settings.setAccent(accent);
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(brightness: brightness, accent: accent),
            builder: foruiBuilder,
            home: SettingsPage(
              settings: settings,
              systemFrame: true,
              onClose: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mark = find.byIcon(CupertinoIcons.check_mark);
        final context = tester.element(mark);
        final foreground =
            tester.widget<Icon>(mark).color ?? IconTheme.of(context).color!;
        expect(foreground, Colors.white);
        final text = DefaultTextStyle.of(
          tester.element(find.text(accent.label)),
        ).style.color!;
        expect(text, Colors.white);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      }
    }
  });
  testWidgets(
    'slider value tooltip stays readable during hover and drag for every theme',
    (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      addTearDown(mouse.removePointer);
      for (final brightness in Brightness.values) {
        for (final accent in ThemeAccent.values) {
          var value = 64.0;
          await tester.pumpWidget(
            MaterialApp(
              theme: desktopTheme(brightness: brightness, accent: accent),
              builder: foruiBuilder,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 240,
                    child: StatefulBuilder(
                      builder: (_, setState) => DesktopSlider(
                        value: value,
                        min: 12,
                        max: 128,
                        onChanged: (next) => setState(() => value = next),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final thumb = tester.getCenter(find.byType(FTooltip));
          await mouse.moveTo(thumb);
          await tester.pumpAndSettle();
          void readable() {
            final label = find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  RegExp(r'^\d+$').hasMatch(widget.data ?? ''),
            );
            expect(label, findsOneWidget);
            final foreground = DefaultTextStyle.of(tester.element(label))
                .style
                .color;
            expect(
              foreground,
              isNotNull,
              reason: 'The tooltip must specify its text color.',
            );
            final decoration = tester
                .widget<DecoratedBox>(
                  find
                      .ancestor(of: label, matching: find.byType(DecoratedBox))
                      .first,
                )
                .decoration;
            expect(
              contrast(foreground!, decorationColor(decoration)),
              greaterThanOrEqualTo(4.5),
              reason: '$brightness $accent',
            );
          }

          readable();
          final drag = await tester.startGesture(thumb);
          await drag.moveBy(const Offset(30, 0));
          await tester.pumpAndSettle();
          readable();
          await drag.up();
          await mouse.moveTo(const Offset(700, 500));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets(
    'general tooltip and Material numeric indicators use readable color pairs',
    (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(brightness: brightness),
            builder: foruiBuilder,
            home: const Scaffold(
              body: Center(
                child: Tooltip(message: 'hint', child: Text('target')),
              ),
            ),
          ),
        );
        final context = tester.element(find.text('target'));
        final theme = Theme.of(context);
        final tooltip = theme.tooltipTheme;
        expect(
          contrast(
            tooltip.textStyle!.color!,
            decorationColor(tooltip.decoration!),
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(
            theme.sliderTheme.valueIndicatorTextStyle!.color!,
            theme.sliderTheme.valueIndicatorColor!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        tester.state<TooltipState>(find.byType(Tooltip)).ensureTooltipVisible();
        await tester.pumpAndSettle();
        expect(find.text('hint'), findsOneWidget);
        final foreground = DefaultTextStyle.of(
          tester.element(find.text('hint')),
        ).style.color!;
        expect(
          contrast(foreground, decorationColor(tooltip.decoration!)),
          greaterThanOrEqualTo(4.5),
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
