import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_context_menu.dart';

void main() {
  testWidgets('unselected controls and open menus follow theme changes', (
    tester,
  ) async {
    final brightness = ValueNotifier(Brightness.light);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: brightness,
        builder: (_, value, _) => MaterialApp(
          theme: desktopTheme(brightness: value),
          builder: foruiBuilder,
          home: Scaffold(
            body: Column(
              children: [
                DesktopIconButton(
                  icon: const Icon(Icons.folder),
                  onPressed: () {},
                ),
                DesktopButton(onPressed: () {}, child: const Text('用应用打开')),
                const SizedBox(width: 160, child: FTextField(hint: '搜索')),
                FileContextMenu(
                  primaryClick: true,
                  onOpen: () {},
                  onOpenWith: (_) {},
                  applications: () async => [],
                  onChooseApplication: () {},
                  child: const SizedBox(
                    key: ValueKey('menu-target'),
                    width: 80,
                    height: 32,
                    child: Text('菜单'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('menu-target')));
    await tester.pumpAndSettle();
    expect(find.text('打开方式'), findsOneWidget);
    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();
    final buttonText = DefaultTextStyle.of(tester.element(find.text('用应用打开')))
        .style
        .color!;
    final toolbarIcon = IconTheme.of(tester.element(find.byIcon(Icons.folder)))
        .color!;
    final input = tester.widget<TextField>(find.byType(TextField));
    final menuText = DefaultTextStyle.of(tester.element(find.text('打开')))
        .style
        .color!;
    expect(buttonText.computeLuminance(), greaterThan(.5));
    expect(toolbarIcon.computeLuminance(), greaterThan(.5));
    expect(input.decoration!.fillColor!.computeLuminance(), lessThan(.15));
    expect(input.style!.color!.computeLuminance(), greaterThan(.5));
    expect(menuText.computeLuminance(), greaterThan(.5));
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((box) => box.color != null)
          .any((box) => box.color!.computeLuminance() > .8),
      false,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    brightness.dispose();
  });

  testWidgets(
    'upward application menu toggles arrow and dismisses on second click',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness: Brightness.dark),
          builder: foruiBuilder,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: FileContextMenu(
                primaryClick: true,
                openUpwards: true,
                applicationOnly: true,
                applications: () async => [],
                onChooseApplication: () {},
                childBuilder: (_, shown, _) => SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    shown
                        ? CupertinoIcons.chevron_down
                        : CupertinoIcons.chevron_up,
                  ),
                ),
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
      expect(find.text('其他…'), findsOneWidget);
      final arrow = tester.getRect(find.byIcon(CupertinoIcons.chevron_down));
      expect(
        tester.getRect(find.text('其他…')).bottom,
        lessThanOrEqualTo(arrow.top),
      );
      await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
      await tester.pumpAndSettle();
      expect(find.text('其他…'), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);
      expect(find.text('其他…'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
