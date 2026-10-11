import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:hizip/services/task_windows.dart';
import 'package:hizip/models/archive_properties.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/archive_comment_field.dart';
import 'package:hizip/ui/desktop_widgets.dart';

class CommentService extends ArchiveService {
  String? saved, originalComment;
  bool fail = false;
  int writes = 0;

  @override
  Future<ArchiveDocument> writeComment(
    ArchiveDocument doc,
    String comment, {
    required String original,
  }) async {
    writes++;
    if (fail) throw StateError('Comment write failed');
    saved = comment;
    originalComment = original;
    return ArchiveDocument(
      doc.path,
      doc.entries,
      doc.format,
      doc.writable,
      comment: comment,
    );
  }
}

class CommentPropertiesWindow extends PropertiesWindowTransport {
  PropertiesWindowAction? action;
  Map<String, dynamic>? data;
  @override
  Future<bool> show(
    Map<String, dynamic> data,
    PropertiesWindowAction action,
  ) async {
    this.data = data;
    this.action = action;
    return true;
  }

  @override
  void dispose() {}
}

void main() {
  setUpAll(() async {
    final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (await font.exists()) {
      final loader = FontLoader('.AppleSystemUIFont')
        ..addFont(
          font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  const section = ValueKey('archive-comment-section');
  const edit = ValueKey('archive-comment-edit');
  const input = ValueKey('archive-comment-input');
  const save = ValueKey('archive-comment-save');
  const empty = ValueKey('archive-comment-empty');
  const expand = ValueKey('archive-comment-expand');
  const content = ValueKey('archive-comment-content');
  late CommentService service;
  late GlobalKey preview;

  Future<void> mount(
    WidgetTester tester, {
    String comment = 'Read me first.\n请先阅读说明。',
    bool writable = true,
    String format = 'ZIP',
    String view = 'list',
    Brightness brightness = Brightness.light,
    AppLanguage language = AppLanguage.simplifiedChinese,
    CommentPropertiesWindow? propertiesWindow,
    bool standaloneProperties = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          DesktopIntegration.channel,
          (_) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopIntegration.channel, null),
    );
    final settings = AppSettings(
      read: () async => null,
      write: (_) async {},
      readLanguage: () async => language.name,
      writeLanguage: (_) async {},
      writeBrowsing: (_) async {},
    );
    await settings.setLanguage(language);
    await settings.setBrowsing(
      BrowsingPreferences(view: view, inspector: true),
    );
    addTearDown(settings.dispose);
    service = CommentService();
    preview = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: MaterialApp(
          theme: desktopTheme(brightness: brightness),
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            propertiesWindowFactory: propertiesWindow == null
                ? null
                : () => propertiesWindow,
            propertiesData: standaloneProperties
                ? archivePropertiesSnapshot(
                    ArchiveDocument(
                      '/sample.zip',
                      const [],
                      'ZIP',
                      writable,
                      comment: comment,
                    ),
                    '',
                    [],
                  )
                : null,
            propertiesAction: (action, data) async {
              final doc = ArchiveDocument(
                '/sample.zip',
                const [],
                'ZIP',
                writable,
                comment: comment,
              );
              final updated = await service.writeComment(
                doc,
                data['text'] as String,
                original: data['original'] as String,
              );
              return archivePropertiesSnapshot(updated, '', []);
            },
            settings: settings,
            initialDocument: ArchiveDocument(
              '/sample.zip',
              const [
                ArchiveEntry(
                  path: 'docs/readme.txt',
                  size: 8,
                  directory: false,
                ),
              ],
              format,
              writable,
              comment: comment,
            ),
            service: service,
            desktop: DesktopIntegration(),
            enableNativeTransfers: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> editComment(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.byKey(edit));
    await tester.tap(find.byKey(edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(input), text);
    await tester.pump();
  }

  testWidgets(
    'Comment follows Status inside Information and hides in folders',
    (tester) async {
      await mount(tester);
      final information = find.byKey(const ValueKey('inspector-information'));
      final status = find.descendant(
        of: information,
        matching: find.text('可写入'),
      );
      expect(
        find.descendant(of: information, matching: find.byKey(section)),
        findsOneWidget,
      );
      expect(find.text('注释'), findsOneWidget);
      expect(find.text('压缩包注释'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(section)).dy -
            tester.getBottomLeft(status).dy,
        lessThan(12),
      );
      await tester.tap(find.byKey(const ValueKey('tree-docs')));
      await tester.pumpAndSettle();
      expect(find.byKey(section), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tree-')));
      await tester.pumpAndSettle();
      expect(find.byKey(section), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty comment stays on the label row and supports inline creation',
    (tester) async {
      await mount(tester, comment: '', language: AppLanguage.english);
      expect(find.text('No comment'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Comment')).dy,
        closeTo(tester.getTopLeft(find.text('No comment')).dy, 1),
      );
      await tester.tap(find.byKey(empty));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(input), 'New comment');
      await tester.pump();
      await tester.tap(find.byKey(save));
      await tester.pumpAndSettle();
      expect(service.saved, 'New comment');
      expect(service.originalComment, '');
      expect(find.byKey(input), findsNothing);
      expect(tester.widget<Text>(find.byKey(content)).data, 'New comment');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('comment uses the same label and value styles as Information', (
    tester,
  ) async {
    await mount(tester);
    AppText label(String text) => tester.widget<AppText>(
      find.ancestor(of: find.text(text), matching: find.byType(AppText)).first,
    );
    expect(label('注释').style, label('状态').style);
    expect(
      tester.widget<Text>(find.byKey(content)).style,
      tester.widget<Text>(find.text('可写入')).style,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'independent property window saves comments through the main window',
    (tester) async {
      final window = CommentPropertiesWindow();
      await mount(
        tester,
        comment: 'Original comment',
        propertiesWindow: window,
      );
      await tester.tap(
        find.byKey(const ValueKey('tree-')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('属性'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final updated = await window.action!('saveComment', {
        'text': 'Saved through Properties',
        'original': 'Original comment',
      });
      await tester.pumpAndSettle();
      expect(updated['comment'], 'Saved through Properties');
      expect(service.saved, 'Saved through Properties');
      expect(
        tester.widget<Text>(find.byKey(content)).data,
        'Saved through Properties',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'standalone property page reuses Gallery layout and inline comment editor',
    (tester) async {
      await mount(
        tester,
        comment: 'Original comment',
        standaloneProperties: true,
      );
      expect(
        find.byKey(const ValueKey('properties-window-page')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('inspector-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-top-bar')), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byKey(edit));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(input), 'Edited in standalone window');
      await tester.pump();
      await tester.tap(find.byKey(save));
      await tester.pumpAndSettle();
      expect(service.saved, 'Edited in standalone window');
      expect(
        tester.widget<Text>(find.byKey(content)).data,
        'Edited in standalone window',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('inline comment grows, saves and can be cleared', (tester) async {
    await mount(tester, comment: 'Original comment');
    await editComment(tester, 'One line');
    final shortHeight = tester.getSize(find.byKey(input)).height;
    final updated = List.filled(8, 'Comment line').join('\n');
    await tester.enterText(find.byKey(input), updated);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(input)).height,
      greaterThan(shortHeight * 2),
    );
    await tester.ensureVisible(find.byKey(save));
    await tester.tap(find.byKey(save));
    await tester.pumpAndSettle();
    expect(service.originalComment, 'Original comment');
    expect(service.saved, updated);
    expect(service.writes, 1);
    await editComment(tester, '');
    await tester.tap(find.byKey(save));
    await tester.pumpAndSettle();
    expect(service.saved, '');
    expect(find.text('暂无注释'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clicking outside saves once and preserves navigation', (
    tester,
  ) async {
    await mount(tester, comment: 'Original comment');
    await editComment(tester, 'Auto saved');
    await tester.tap(find.byKey(const ValueKey('tree-docs')));
    await tester.pumpAndSettle();
    expect(service.saved, 'Auto saved');
    expect(service.writes, 1);
    expect(find.byKey(const ValueKey('file-docs/readme.txt')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tree-')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(content)).data, 'Auto saved');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed auto save retains the draft across directory changes', (
    tester,
  ) async {
    await mount(tester, comment: 'Original comment');
    service.fail = true;
    await editComment(tester, 'Retained draft');
    await tester.tap(find.byKey(const ValueKey('tree-docs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DesktopTextField>(find.byKey(input)).controller.text,
      'Retained draft',
    );
    expect(find.text('Comment write failed'), findsWidgets);
    service.fail = false;
    await tester.ensureVisible(find.byKey(save));
    await tester.tap(find.byKey(save));
    await tester.pumpAndSettle();
    expect(service.saved, 'Retained draft');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'read-only comments expand but do not edit, other formats hide the row',
    (tester) async {
      await mount(
        tester,
        writable: false,
        comment: List.filled(10, 'Read only').join('\n'),
      );
      await tester.tap(find.byKey(edit));
      await tester.pumpAndSettle();
      expect(find.byKey(input), findsNothing);
      await tester.ensureVisible(find.byKey(expand));
      await tester.tap(find.byKey(expand));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(content)).maxLines, isNull);
      expect(service.saved, isNull);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, format: '7z');
      expect(find.byKey(section), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('UTF-8 limit rejects oversized drafts without losing input', () async {
    final draft = ArchiveCommentDraft();
    addTearDown(draft.dispose);
    var writes = 0;
    draft.begin('', (_, _) async => writes++);
    draft.input.text = '汉' * 22000;
    await draft.save();
    expect(writes, 0);
    expect(draft.editing, isTrue);
    expect(draft.input.text.length, 22000);
    expect(draft.error, isNotNull);
    draft.input.text = 'Within limit';
    await draft.save();
    expect(writes, 1);
    expect(draft.editing, isFalse);
  });

  for (final view in ['list', 'gallery']) {
    testWidgets(
      'comment collapses and expands in $view at minimum inspector width',
      (tester) async {
        final longComment = List.filled(
          30,
          'Long archive comment 注释内容',
        ).join('\n');
        await mount(
          tester,
          comment: longComment,
          view: view,
          brightness: Brightness.dark,
          language: AppLanguage.german,
        );
        tester.view.physicalSize = const Size(800, 500);
        await tester.pumpAndSettle();
        if (view == 'gallery') {
          final strip = tester.getRect(
            find.byKey(const ValueKey('gallery-filmstrip')),
          );
          await tester.tapAt(Offset(strip.right - 8, strip.center.dy));
          await tester.pumpAndSettle();
        }
        expect(find.text('Kommentar'), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(content)).maxLines, 4);
        expect(
          tester.getSize(find.byKey(content)).height,
          lessThanOrEqualTo(80),
        );
        await tester.ensureVisible(find.byKey(expand));
        await tester.tap(find.byKey(expand));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(content)).maxLines, isNull);
        expect(tester.getSize(find.byKey(content)).height, greaterThan(300));
        await tester.ensureVisible(find.byKey(expand));
        await tester.tap(find.byKey(expand));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(content)).maxLines, 4);
        await tester.ensureVisible(find.byKey(content));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              preview.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final screenshot = await boundary.toImage();
          final data = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('/tmp/hizip-comment-$view.png')
              .writeAsBytes(data!.buffer.asUint8List());
          screenshot.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
