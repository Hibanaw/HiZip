import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/models/selection_highlight.dart';
import 'package:hizip/models/theme_accent.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/settings_page.dart';

void main() {
  testWidgets('standalone settings applies dark theme and closes with Escape', (
    tester,
  ) async {
    var closed = false;
    final settings = AppSettings(
      read: () async => null,
      write: (_) async {},
      readTheme: () async => null,
      writeTheme: (_) async {},
      writeHighlight: (_) async {},
      writeAccent: (_) async {},
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: settings,
        builder: (_, _) => MaterialApp(
          theme: desktopTheme(accent: settings.accent),
          darkTheme: desktopTheme(
            brightness: Brightness.dark,
            accent: settings.accent,
          ),
          themeMode: settings.themeMode,
          builder: foruiBuilder,
          home: SettingsPage(
            settings: settings,
            systemFrame: true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    expect(find.text('解压线程数'), findsNothing);
    expect(
      find.text('设置'),
      findsNothing,
    ); // The operating system owns the titlebar.
    await tester.tap(find.text('性能'));
    await tester.pumpAndSettle();
    expect(find.text('解压线程数'), findsOneWidget);
    expect(find.text('深色'), findsNothing);
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    expect(find.text('文件选择高亮'), findsNothing);
    expect(find.text('淡灰色'), findsNothing);
    await tester.ensureVisible(find.text('紫色'));
    await tester.tap(find.text('紫色'));
    await tester.pumpAndSettle();
    expect(settings.accent, ThemeAccent.purple);
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).colorScheme.primary,
      ThemeAccent.purple.color,
    );
    expect(find.byTooltip('返回'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
  test(
    'file highlight persists and invalid preferences fall back to blue',
    () async {
      String? stored;
      AppSettings create() => AppSettings(
        read: () async => null,
        write: (_) async {},
        readHighlight: () async => stored,
        writeHighlight: (value) async {
          stored = value;
        },
      );
      final first = create();
      await first.setSelectionHighlight(SelectionHighlight.neutral);
      final second = create();
      await second.load();
      expect(second.selectionHighlight, SelectionHighlight.blue);
      await second.setSelectionHighlight(SelectionHighlight.blue);
      await first.load();
      expect(first.selectionHighlight, SelectionHighlight.blue);
      stored = 'invalid';
      await second.load();
      expect(second.selectionHighlight, SelectionHighlight.blue);
      first.dispose();
      second.dispose();
    },
  );

  test('failed file highlight save retains its working preference', () async {
    final settings = AppSettings(
      writeHighlight: (_) async {
        throw StateError('disk');
      },
    );
    await settings.setSelectionHighlight(SelectionHighlight.neutral);
    expect(settings.selectionHighlight, SelectionHighlight.blue);
    expect(settings.error, isNotNull);
    settings.dispose();
  });

  test('appearance persists across settings instances', () async {
    String? stored;
    AppSettings create() => AppSettings(
      read: () async => null,
      write: (_) async {},
      readTheme: () async => stored,
      writeTheme: (value) async {
        stored = value;
      },
    );
    final first = create();
    await first.setThemeMode(ThemeMode.dark);
    final second = create();
    await second.load();
    expect(second.themeMode, ThemeMode.dark);
    stored = 'invalid';
    await second.load();
    expect(second.themeMode, ThemeMode.system);
    first.dispose();
    second.dispose();
  });

  test('DPI scale persists and clamps unsafe values', () async {
    String? stored;
    AppSettings create() => AppSettings(
      read: () async => null,
      write: (_) async {},
      readDpiScale: () async => stored,
      writeDpiScale: (value) async => stored = value,
    );
    final first = create();
    await first.setDpiScale(1.25);
    expect(first.dpiScale, 1.25);
    final second = create();
    await second.load();
    expect(second.dpiScale, 1.25);
    await second.setDpiScale(2);
    expect(second.dpiScale, 1.5);
    first.dispose();
    second.dispose();
  });
  test(
    'thread preference persists and invalid values fall back to auto',
    () async {
      int? stored;
      AppSettings create() => AppSettings(
        read: () async => stored,
        write: (value) async {
          stored = value;
        },
      );
      final first = create();
      await first.setExtractionWorkers(2);
      final second = create();
      await second.load();
      expect(second.extractionWorkers, 2);
      await second.setExtractionWorkers(null);
      expect(stored, 0);
      stored = 999;
      await second.load();
      expect(second.extractionWorkers, isNull);
      first.dispose();
      second.dispose();
    },
  );

  test('failed persistence retains the previous working value', () async {
    final settings = AppSettings(
      read: () async => 2,
      write: (_) async {
        throw StateError('disk');
      },
    );
    await settings.load();
    await settings.setExtractionWorkers(4);
    expect(settings.extractionWorkers, 2);
    expect(settings.error, isNotNull);
    settings.dispose();
  });

  testWidgets(
    'settings shortcut opens performance and applies the choice to extraction',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      final service = ArchiveService();
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(),
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            settings: settings,
            service: service,
            enableNativeTransfers: false,
          ),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.tap(find.text('性能'));
      await tester.pumpAndSettle();
      expect(find.text('解压线程数'), findsOneWidget);
      await tester.tap(find.text('2 个线程'));
      await tester.pumpAndSettle();
      expect(service.maxExtractionWorkers, 2);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets('performance settings fit narrow windows', (tester) async {
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(read: () async => null, write: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: SettingsPage(settings: settings),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('性能'));
    await tester.pumpAndSettle();
    expect(find.text('4 个线程'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
  testWidgets(
    'archive settings show independent defaults and fit narrow windows',
    (tester) async {
      tester.view.physicalSize = const Size(440, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? stored;
      final settings = AppSettings(
        writeArchive: (value) async {
          stored = value;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(),
          builder: foruiBuilder,
          home: SettingsPage(settings: settings),
        ),
      );
      await tester.tap(find.text('压缩包'));
      await tester.pumpAndSettle();
      expect(find.text('读取默认文件名编码'), findsOneWidget);
      final pickers = tester
          .widgetList<DesktopSelect<String>>(find.byType(DesktopSelect<String>))
          .toList();
      expect(pickers[0].value, 'auto');
      expect(pickers[1].value, 'UTF-8');
      expect(pickers[1].items.containsValue('auto'), false);
      await tester.tap(find.byType(DesktopSelect<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文（GB18030 / GBK）').last);
      await tester.pumpAndSettle();
      expect(settings.archive.readEncoding, 'GB18030');
      expect(settings.archive.createEncoding, 'UTF-8');
      expect(stored, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
