import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/settings_page.dart';

void main() {
  testWidgets('default association changes only after the settings action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopIntegration.channel, (call) async {
          calls.add(call.method);
          return call.method == 'setDefaultArchiveHandler' ? 20 : null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopIntegration.channel, null);
    });
    final settings = AppSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: SettingsPage(settings: settings),
      ),
    );
    await tester.tap(find.text('通用'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('setDefaultArchiveHandler')));
    await tester.tap(find.text('设为默认打开方式'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'setDefaultArchiveHandler').length, 1);
    expect(find.text('已设为默认打开方式'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('default association is available on Linux without Quick Look', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final settings = AppSettings();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      settings.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: SettingsPage(settings: settings),
      ),
    );
    await tester.tap(find.text('通用'));
    await tester.pumpAndSettle();
    final desktop = DesktopIntegration();
    expect(desktop.supportsDefaultApplication, isTrue);
    expect(desktop.supportsQuickLook, isFalse);
    final button = tester.widget<DesktopButton>(
      find.ancestor(
        of: find.text('设为默认打开方式'),
        matching: find.byType(DesktopButton),
      ),
    );
    expect(button.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
