import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hizip/main.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/ui/window_chrome.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Application menu cascades beside its parent on HarmonyOS', (
    tester,
  ) async {
    await initializeWindowChrome();
    await AppSettings.instance.load();
    AppSettings.instance.language = AppLanguage.simplifiedChinese;
    final screenshot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: screenshot, child: const HiZipApp()),
    );

    Future<void> waitFor(Finder finder) async {
      for (var attempt = 0; attempt < 50; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
      }
      fail('Menu did not appear: $finder');
    }

    Rect panel(String label) {
      final group = find
          .ancestor(of: find.text(label), matching: find.byType(FItemGroup))
          .evaluate()
          .firstWhere(
            (element) => (element.widget as FItemGroup).maxHeight.isFinite,
          );
      return tester.getRect(find.byWidget(group.widget));
    }

    await waitFor(find.byTooltip('应用菜单'));
    await tester.tap(find.byTooltip('应用菜单'));
    await waitFor(find.text('文件'));
    final parent = panel('文件');
    await tester.tap(find.text('文件'));
    await waitFor(find.text('最近打开'));
    final child = panel('最近打开');
    expect(child.left, greaterThanOrEqualTo(parent.right - 8));
    await tester.tap(find.text('最近打开'));
    await waitFor(find.text('清除菜单'));
    final grandchild = panel('清除菜单');
    expect(grandchild.left, greaterThanOrEqualTo(child.right - 8));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 200));
    final boundary =
        screenshot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      binding.reportData = {
        'menuScreenshotBase64': base64Encode(bytes!.buffer.asUint8List()),
        'menuBounds': [
          for (final rect in [parent, child, grandchild])
            {
              'left': rect.left,
              'right': rect.right,
              'top': rect.top,
              'bottom': rect.bottom,
            },
        ],
      };
    } finally {
      image.dispose();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('最近打开'), findsNothing);
    expect(find.text('清除菜单'), findsNothing);
  });
}
