import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';
import 'package:hizip/models/selection_highlight.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('selected controls remain readable in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness: brightness),
          builder: foruiBuilder,
          home: Scaffold(
            body: DesktopButton(
              active: true,
              flat: true,
              onPressed: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.folder), Text('选中')],
              ),
            ),
          ),
        ),
      );
      final foreground = DefaultTextStyle.of(tester.element(find.text('选中')))
          .style
          .color!;
      final background = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((box) => box.color)
          .whereType<Color>()
          .firstWhere(
            (color) =>
                color ==
                desktopSelectionBackground(tester.element(find.text('选中'))),
          );
      final a = foreground.computeLuminance() + .05;
      final b = background.computeLuminance() + .05;
      final ratio = a > b ? a / b : b / a;
      expect((background.r - background.b).abs(), lessThan(.025));
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.folder))).color,
        foreground,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final highlight in SelectionHighlight.values) {
      testWidgets('file text stays readable for $highlight in $brightness', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(brightness: brightness),
            home: const Scaffold(body: Text('file')),
          ),
        );
        final context = tester.element(find.text('file'));
        final background =
            fileSelectionBackground(context, highlight).computeLuminance() +
            .05;
        for (final secondary in [false, true]) {
          final foreground =
              fileSelectionForeground(
                context,
                highlight,
                secondary: secondary,
              ).computeLuminance() +
              .05;
          expect(
            foreground > background
                ? foreground / background
                : background / foreground,
            greaterThanOrEqualTo(4.5),
          );
        }
      });
    }
  }

  testWidgets('column ancestors retain a subtle neutral highlight', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: FileItemSurface(
            name: 'parent',
            selected: true,
            activeSelection: false,
            onSelect: () {},
            onActivate: () {},
            child: const Text('parent'),
          ),
        ),
      ),
    );
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(FileItemSurface),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect((decoration.color!.r - decoration.color!.b).abs(), lessThan(.025));
  });
}
