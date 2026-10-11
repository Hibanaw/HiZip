import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

class _Service extends ArchiveService {
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip'],
  };
  @override
  Future<Uint8List> preview(
    ArchiveDocument document,
    ArchiveEntry entry,
  ) async => Uint8List(0);
}

class _Desktop extends DesktopIntegration {
  bool fileCommands = false;
  @override
  bool get supportsQuickLook => false;
  @override
  bool get supportsMenuBar => false;
  @override
  Future<void> enableFileCommands(bool enabled) async => fileCommands = enabled;
}

void main() {
  Future<_Desktop> mount(
    WidgetTester tester, {
    double scale = 1,
    String view = 'list',
    double iconSize = 22,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(writeBrowsing: (_) async {});
    await settings.setBrowsing(
      BrowsingPreferences(
        view: view,
        inspector: false,
        listIconSize: iconSize,
        columnIconSize: iconSize,
      ),
    );
    addTearDown(settings.dispose);
    final desktop = _Desktop();
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(brightness: brightness),
        builder: (context, child) => foruiBuilder(
          context,
          MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: ArchiveWorkspace(
          settings: settings,
          desktop: desktop,
          service: _Service(),
          enableNativeTransfers: false,
          initialDocument: ArchiveDocument(
            '/sample.zip',
            const [ArchiveEntry(path: '中文文件.txt', size: 7, directory: false)],
            'ZIP',
            true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return desktop;
  }

  void fits(WidgetTester tester, Finder field, {double padding = 10}) {
    final editableFinder = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final editable = tester
        .state<EditableTextState>(editableFinder)
        .renderEditable;
    expect(
      editable.size.height,
      greaterThanOrEqualTo(editable.preferredLineHeight),
      reason: 'The input viewport must fit the entire text line and cursor.',
    );
    final container = InputDecorator.containerOf(
      tester.element(editableFinder),
    )!;
    final box = container.localToGlobal(Offset.zero) & container.size;
    expect(
      box.height,
      greaterThanOrEqualTo(editable.preferredLineHeight + padding),
      reason:
          'The painted border needs vertical padding, not just the outer box.',
    );
    expect(box.center.dy, closeTo(tester.getRect(field).center.dy, 1));
    final input = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.controller ==
                tester.widget<EditableText>(editableFinder).controller,
      ),
    );
    final offset = editable.localToGlobal(Offset.zero);
    for (final glyphs in editable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: input.controller!.text.length),
    )) {
      final line = glyphs.toRect().shift(offset);
      expect(
        line.top,
        greaterThanOrEqualTo(box.top + 2),
        reason: 'Painted glyphs must remain clear of the top border.',
      );
      expect(
        line.bottom,
        lessThanOrEqualTo(box.bottom - 2),
        reason: 'Painted glyphs must remain clear of the bottom border.',
      );
      // Glyph bounds can differ slightly from the full line's font metrics.
      expect(line.center.dy, closeTo(box.center.dy, 2));
    }
    final caret = editable
        .getLocalRectForCaret(const TextPosition(offset: 0))
        .shift(offset);
    expect(caret.top, greaterThanOrEqualTo(box.top + 2));
    expect(caret.bottom, lessThanOrEqualTo(box.bottom - 2));
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'search text fits at $scale in $brightness and clear keeps focus',
        (tester) async {
          await mount(tester, scale: scale, brightness: brightness);
          await tester.tap(find.byTooltip('搜索'));
          await tester.pumpAndSettle();
          final search = find.byType(TextField);
          fits(tester, search);
          await tester.enterText(search, '中文');
          await tester.pump();
          fits(tester, search);
          final bar = tester.getRect(
            find.byKey(const ValueKey('workspace-search-bar')),
          );
          final searchBounds = tester.getRect(search);
          expect(searchBounds.top, greaterThanOrEqualTo(bar.top));
          expect(searchBounds.bottom, lessThanOrEqualTo(bar.bottom));
          expect(searchBounds.center.dy, closeTo(bar.center.dy, 1));
          await tester.tap(find.byKey(const ValueKey('clear-archive-search')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
          expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final view in ['list', 'grid', 'columns', 'gallery']) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('$view rename fits at text size $scale', (tester) async {
        await mount(tester, scale: scale, view: view);
        await tester.tap(find.byKey(const ValueKey('file-中文文件.txt')));
        await tester.pumpAndSettle();
        final originalBounds = tester.getRect(
          find.byKey(const ValueKey('file-中文文件.txt')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        final rename = find.byKey(const ValueKey('rename-entry-name'));
        fits(tester, rename, padding: 4);
        final fileBounds = tester.getRect(
          find.byKey(const ValueKey('file-中文文件.txt')),
        );
        final renameBounds = tester.getRect(rename);
        expect(renameBounds.top, greaterThanOrEqualTo(fileBounds.top));
        expect(renameBounds.bottom, lessThanOrEqualTo(fileBounds.bottom));
        if (view == 'list' || view == 'columns') {
          expect(
            fileBounds,
            originalBounds,
            reason: 'Renaming must preserve row height and position.',
          );
          expect(renameBounds.center.dy, closeTo(fileBounds.center.dy, 1));
        }
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: rename, matching: find.byType(TextField)),
              )
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final view in ['list', 'columns']) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('$view rename preserves smallest rows at scale $scale', (
        tester,
      ) async {
        await mount(tester, view: view, scale: scale, iconSize: 12);
        final file = find.byKey(const ValueKey('file-中文文件.txt'));
        final original = tester.getRect(file);
        await tester.tap(file);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        expect(tester.getRect(file), original);
        fits(
          tester,
          find.byKey(const ValueKey('rename-entry-name')),
          padding: 4,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.getRect(file), original);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'macOS search and rename keep the caret inside the painted border',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await mount(tester);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      fits(tester, find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-中文文件.txt')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      fits(tester, find.byKey(const ValueKey('rename-entry-name')));
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('native file commands follow text-input focus', (tester) async {
    final desktop = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('file-中文文件.txt')));
    await tester.pumpAndSettle();
    expect(desktop.fileCommands, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(desktop.fileCommands, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(desktop.fileCommands, isTrue);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(desktop.fileCommands, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
