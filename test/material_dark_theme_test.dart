import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/theme_accent.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
  for (final accent in ThemeAccent.values) {
    test('${accent.name} derives Material defaults from dark brightness', () {
      final theme = desktopTheme(brightness: Brightness.dark, accent: accent);
      final colors = theme.colorScheme;
      expect(theme.canvasColor, colors.surface);
      expect(theme.cardColor, colors.surface);
      expect(theme.dialogTheme.backgroundColor, colors.surface);
      expect(theme.drawerTheme.backgroundColor, colors.surface);
      expect(theme.primaryColor, colors.primary);
      expect(colors.secondary, colors.primary);
      expect(theme.iconTheme.color!.computeLuminance(), greaterThan(.5));
      expect(
        theme.textTheme.titleLarge!.color!.computeLuminance(),
        greaterThan(.5),
      );
      expect(
        theme.textTheme.bodyLarge!.color!.computeLuminance(),
        greaterThan(.5),
      );
      final errorContrast =
          (colors.error.computeLuminance() + .05) /
          (colors.surface.computeLuminance() + .05);
      expect(errorContrast, greaterThanOrEqualTo(4.5));
      final accentText = theme.textButtonTheme.style!.foregroundColor!.resolve(
        {},
      )!;
      expect(
        (accentText.computeLuminance() + .05) /
            (colors.surface.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      final thumb = theme.scrollbarTheme.thumbColor!.resolve({})!;
      expect(thumb.computeLuminance(), lessThan(.25));
      expect(theme.disabledColor.computeLuminance(), greaterThan(.5));
    });
  }

  testWidgets('compression dialog and its dropdown update to dark surfaces', (
    tester,
  ) async {
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: brightness,
        builder: (_, value, _) => MaterialApp(
          builder: foruiBuilder,
          theme: desktopTheme(brightness: value, accent: ThemeAccent.purple),
          home: const ArchiveCreateDialog(
            format: 'zip',
            aesAvailable: true,
            initialLevel: 6,
          ),
        ),
      ),
    );
    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(FDialog));
    final colors = Theme.of(context).colorScheme;
    expect(FTheme.of(context).colors.background, colors.surface);
    expect(find.byType(AlertDialog), findsNothing);
    final title = DefaultTextStyle.of(tester.element(find.text('压缩选项'))).style;
    expect(title.color!.computeLuminance(), greaterThan(.5));
    await tester.tap(find.byKey(const ValueKey('zip-encryption')));
    await tester.pumpAndSettle();
    final editable = tester.widgetList<EditableText>(find.byType(EditableText));
    for (final input in editable) {
      expect(input.style.color!.computeLuminance(), greaterThan(.5));
      expect(input.cursorColor, desktopAccentForeground(context));
    }
    await tester.tap(find.text('创建'));
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('密码不能为空，两次输入必须一致。')).style?.color,
      colors.error,
    );
    await tester.tap(find.text('Deflate'));
    await tester.pumpAndSettle();
    final surfaces = tester
        .widgetList<Material>(find.byType(Material))
        .where(
          (material) =>
              material.color != null &&
              material.type != MaterialType.transparency,
        );
    expect(
      surfaces.every((material) => material.color!.computeLuminance() < .2),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
