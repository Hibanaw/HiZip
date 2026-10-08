import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
  String? stored;
  AppSettings create() => AppSettings(
    read: () async => null,
    write: (_) async {},
    readTheme: () async => null,
    writeTheme: (_) async {},
    readBrowsing: () async => stored,
    writeBrowsing: (value) async {
      stored = value;
    },
  );
  setUp(() => stored = null);

  test('browsing preferences survive a new settings instance', () async {
    final first = create();
    await first.setBrowsing(
      const BrowsingPreferences(
        view: 'columns',
        columnIconSize: 28,
        gridIconSize: 128,
        listIconSize: 16,
        inspector: false,
        sidebarWidth: 280,
        inspectorWidth: 320,
        listSortColumn: 'modified',
        listSortAscending: false,
        listNameWidth: 360,
        listSizeWidth: 100,
        listModifiedWidth: 150,
        listKindWidth: 110,
      ),
    );
    final second = create();
    await second.load();
    expect(second.browsing.toJson(), first.browsing.toJson());
    first.dispose();
    second.dispose();
  });

  test('corrupt and out-of-range preferences use safe defaults', () async {
    stored = 'broken json';
    final settings = create();
    await settings.load();
    expect(settings.browsing.toJson(), const BrowsingPreferences().toJson());
    stored = jsonEncode({
      'view': 'old-view',
      'iconSize': 500,
      'inspector': 'invalid',
      'sidebarWidth': -1,
      'inspectorWidth': 10,
    });
    await settings.load();
    expect(settings.browsing.toJson(), const BrowsingPreferences().toJson());
    settings.dispose();
  });

  test('legacy shared size migrates into the active view only', () {
    final legacy = BrowsingPreferences.fromJson({
      'view': 'columns',
      'iconSize': 72,
    });
    expect(legacy.columnIconSize, 32);
    expect(legacy.listIconSize, 22);
    expect(legacy.gridIconSize, 64);
    final restored = BrowsingPreferences.fromJson(legacy.toJson());
    expect(restored.toJson(), legacy.toJson());
  });

  test('overlapping changes persist the latest layout', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final writes = <String>[];
    final settings = AppSettings(
      writeBrowsing: (value) async {
        writes.add(value);
        if (writes.length == 1) {
          started.complete();
          await gate.future;
        }
        stored = value;
      },
    );
    final first = settings.setBrowsing(
      const BrowsingPreferences(view: 'grid', gridIconSize: 64),
    );
    await started.future;
    settings.setBrowsing(
      const BrowsingPreferences(
        view: 'columns',
        columnIconSize: 28,
        gridIconSize: 128,
        listIconSize: 16,
      ),
    );
    final last = settings.setBrowsing(
      const BrowsingPreferences(
        view: 'grid',
        gridIconSize: 88,
        inspector: false,
      ),
    );
    gate.complete();
    await Future.wait([first, last]);
    expect(writes.length, 2);
    final restored = create();
    await restored.load();
    expect(restored.browsing.toJson(), settings.browsing.toJson());
    settings.dispose();
    restored.dispose();
  });

  testWidgets('workspace restores saved view, icon size and panels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = create();
    await first.setBrowsing(
      const BrowsingPreferences(
        view: 'columns',
        columnIconSize: 28,
        gridIconSize: 128,
        listIconSize: 16,
        inspector: false,
        sidebarWidth: 280,
        inspectorWidth: 320,
      ),
    );
    final restored = create();
    await restored.load();
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          settings: restored,
          enableNativeTransfers: false,
          initialDocument: ArchiveDocument(
            '/sample.zip',
            const [ArchiveEntry(path: 'one.txt', size: 4, directory: false)],
            'ZIP',
            true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    DesktopIconButton button(String tooltip) => tester.widget(
      find.byWidgetPredicate(
        (widget) => widget is DesktopIconButton && widget.tooltip == tooltip,
      ),
    );
    expect(button('多栏视图').active, true);
    expect(tester.widget<DesktopSlider>(find.byType(DesktopSlider)).value, 28);
    expect(find.byKey(const ValueKey('inspector-panel')), findsNothing);
    await tester.tap(find.byTooltip('图标视图'));
    await tester.pumpAndSettle();
    expect(restored.browsing.view, 'grid');
    final next = create();
    await next.load();
    expect(next.browsing.view, 'grid');
    expect(next.browsing.iconSize, 128);
    expect(next.browsing.sidebarWidth, 280);
    DesktopSlider slider() =>
        tester.widget<DesktopSlider>(find.byType(DesktopSlider));
    expect(slider().min, 32);
    expect(slider().max, 256);
    slider().onChanged!(256);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(restored.browsing.gridIconSize, 256);
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(slider().value, 16);
    expect(slider().min, 12);
    expect(slider().max, 36);
    final regularHeight = tester
        .getSize(find.byKey(const ValueKey('file-one.txt')))
        .height;
    slider().onChanged!(12);
    await tester.pumpAndSettle();
    final compactHeight = tester
        .getSize(find.byKey(const ValueKey('file-one.txt')))
        .height;
    expect(compactHeight, lessThan(regularHeight));
    expect(compactHeight, lessThan(24));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('多栏视图'));
    await tester.pumpAndSettle();
    expect(slider().value, 28);
    expect(slider().min, 12);
    expect(slider().max, 32);
    slider().onChanged!(12);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('图标视图'));
    await tester.pumpAndSettle();
    expect(slider().value, 256);
    final persisted = create();
    await persisted.load();
    expect(persisted.browsing.gridIconSize, 256);
    expect(persisted.browsing.listIconSize, 12);
    expect(persisted.browsing.columnIconSize, 12);
    persisted.dispose();
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    restored.dispose();
    next.dispose();
  });
}
