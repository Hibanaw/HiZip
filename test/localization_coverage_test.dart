import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';

void main() {
  test('Chinese interface literals in app sources are registered', () {
    // Dynamic messages are exercised below. Autonyms and a suffix composed
    // into the registered default-app pattern and font metric probes are literal.
    const exclusions = {'日本語', '（默认）', 'Ag国', r'Ag汉字あ한\nAg汉字あ한'};
    final literal = RegExp(r'''(['"])([^'"\n]*[\u4e00-\u9fff][^'"\n]*)\1''');
    final missing = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('/app_localizations.dart') ||
          file.path.endsWith('/translations.dart')) {
        continue;
      }
      for (final match in literal.allMatches(file.readAsStringSync())) {
        final text = match[2]!;
        if (text.contains(r'$') ||
            text.contains('}') ||
            exclusions.contains(text)) {
          continue;
        }
        if (!appEnglishMessages.containsKey(text)) {
          missing.add('${file.path}: $text');
        }
      }
    }
    expect(missing, isEmpty);
  });

  test('macOS template menu titles have registered translations', () {
    final source = File('macos/Runner/Base.lproj/MainMenu.xib')
        .readAsStringSync();
    final titles =
        RegExp(r'<menu(?:Item)?\b[^>]*\btitle="([^"]+)"')
            .allMatches(source)
            .map((match) => match[1]!.replaceAll('APP_NAME', 'HiZip'))
            .toSet()
          ..removeAll({'Main Menu', 'HiZip', 'Preferences…'});
    // Preferences is replaced by the app's Settings command at startup.
    expect(titles.difference(appEnglishMessages.values.toSet()), isEmpty);
  });

  test('warnings and nested errors translate while keeping paths literal', () {
    for (final language in ['en', 'ja', 'ko', 'fr', 'de', 'es']) {
      final messages = [
        '发现 2 个指向绝对路径或解压目录之外的符号链接',
        '发现 2 个指向绝对路径或解压目录之外的符号链接，例如 文件/链接 → /外部/资料。\n\n保留后，解压出的链接会指向压缩包之外的位置。',
        '有 2 个文件仅大小写不同，目标磁盘不区分大小写',
        '有 2 个文件仅大小写不同，目标磁盘不区分大小写，例如 文件/资料.TXT。\n\n自动重命名会保留两个文件（后者加上“ (2)”），跳过则只保留第一个。',
        '解压完成，但已跳过 2 个硬链接或特殊文件；1 个符号链接无法创建；已重命名 3 个仅大小写不同的文件；已跳过 4 个仅大小写不同的文件：/中文/目标：备份',
        '保存失败：Bad state: 目标名称已存在。\n临时文件仍保留在 /中文/文件.txt',
        '设置失败：外观设置保存失败，请重试。',
        '正在解压 1 / 10',
      ];
      for (final message in messages) {
        final translated = translateAppText(message, language);
        expect(translated, isNot(message), reason: '$language: $message');
        expect(translated, isNot(contains('指向绝对路径')));
        expect(translated, isNot(contains('仅大小写不同')));
        expect(translated, isNot(contains('目标名称已存在')));
        if (message.contains('文件/链接')) {
          expect(translated, contains('文件/链接'));
          expect(translated, contains('/外部/资料'));
        }
        if (message.contains('文件/资料.TXT')) {
          expect(translated, contains('文件/资料.TXT'));
        }
        if (message.contains('/中文/目标')) {
          expect(translated, contains('/中文/目标：备份'));
          expect(translated, isNot(contains('已跳过')));
          expect(translated, isNot(contains('符号链接无法创建')));
        }
        if (message.contains('/中文/文件.txt')) {
          expect(translated, contains('/中文/文件.txt'));
          expect(translated, isNot(contains('Bad state:')));
        }
      }
    }
  });

  for (final language in ['en', 'ja', 'ko', 'fr', 'de', 'es']) {
    testWidgets('$language dialog routes retain the caller language', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppLanguageScope(
            languageCode: language,
            child: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      builder: (_) =>
                          ArchivePasswordDialog(onUnlock: (_) async {}),
                    ),
                    child: const Text('password'),
                  ),
                  TextButton(
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      builder: (_) => const ArchiveCreateDialog(
                        format: 'zip',
                        aesAvailable: true,
                        initialLevel: 6,
                      ),
                    ),
                    child: const Text('create'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('password'));
      await tester.pumpAndSettle();
      expect(find.text(translateAppText('输入压缩包密码', language)), findsOneWidget);
      await tester.tap(find.text(translateAppText('取消', language)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('create'));
      await tester.pumpAndSettle();
      expect(find.text(translateAppText('压缩选项', language)), findsOneWidget);
      await tester.tap(find.text(translateAppText('取消', language)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
