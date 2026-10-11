import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';

void main() {
  testWidgets('wrong password stays in dialog and a correct retry closes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => ArchivePasswordDialog(
                onUnlock: (password) async {
                  if (password != 'correct') throw StateError('wrong');
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('archive-password')),
      'wrong',
    );
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('无法解锁：密码错误、格式不受支持或文件已损坏。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('archive-password')),
      'correct',
    );
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.byType(ArchivePasswordDialog), findsNothing);
  });
  testWidgets('unavailable AES is disabled and passwords must match', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveCreateDialog(
          format: 'zip',
          aesAvailable: false,
          initialLevel: 6,
        ),
      ),
    );
    expect(
      tester
          .widget<FCheckbox>(find.byKey(const ValueKey('zip-encryption')))
          .enabled,
      isFalse,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveCreateDialog(
          key: ValueKey('available'),
          format: 'zip',
          aesAvailable: true,
          initialLevel: 6,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('zip-encryption')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('create-password')),
      'one',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-password')),
      'two',
    );
    await tester.tap(find.text('创建'));
    await tester.pump();
    expect(find.text('密码不能为空，两次输入必须一致。'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
