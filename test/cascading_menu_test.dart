import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_context_menu.dart';

void main() {
  for (final platform in TargetPlatform.values) {
    for (final rightEdge in [false, true]) {
      testWidgets(
        '${platform.name} cascades menus ${rightEdge ? 'inside the right edge' : 'right'}',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            tester.view.physicalSize = const Size(1200, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var invoked = false;
            await tester.pumpWidget(
              MaterialApp(
                theme: desktopTheme(),
                builder: foruiBuilder,
                home: Scaffold(
                  body: Align(
                    alignment: rightEdge
                        ? Alignment.topRight
                        : Alignment.topLeft,
                    child: FileContextMenu(
                      primaryClick: true,
                      actions: [
                        DesktopMenuAction(
                          'File',
                          null,
                          children: [
                            DesktopMenuAction(
                              'Recent',
                              null,
                              children: [
                                DesktopMenuAction(
                                  'Recent archive',
                                  () => invoked = true,
                                ),
                              ],
                            ),
                            DesktopMenuAction('Open', () {}),
                          ],
                        ),
                        DesktopMenuAction('Edit', () {}),
                      ],
                      child: const SizedBox(
                        key: ValueKey('menu-trigger'),
                        width: 80,
                        height: 40,
                        child: Text('Menu'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.byKey(const ValueKey('menu-trigger')));
            await tester.pumpAndSettle();
            Rect panel(String label) {
              final group = find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(FItemGroup),
                  )
                  .evaluate()
                  .firstWhere(
                    (element) =>
                        (element.widget as FItemGroup).maxHeight.isFinite,
                  );
              return tester.getRect(find.byWidget(group.widget));
            }

            final parent = panel('File');
            await tester.tap(find.text('File'));
            await tester.pumpAndSettle();
            final child = panel('Recent');
            await tester.tap(find.text('Recent'));
            await tester.pumpAndSettle();
            final grandchild = panel('Recent archive');
            if (rightEdge) {
              expect(child.right, lessThanOrEqualTo(parent.left + 8));
            }
            for (final pair in [(parent, child), (child, grandchild)]) {
              if (rightEdge) {
                expect(
                  pair.$2.right <= pair.$1.left + 8 ||
                      pair.$2.left >= pair.$1.right - 8,
                  isTrue,
                  reason: 'Submenu must sit beside its parent: $pair',
                );
              } else {
                expect(pair.$2.left, greaterThanOrEqualTo(pair.$1.right - 8));
              }
              expect(pair.$2.left, greaterThanOrEqualTo(8));
              expect(pair.$2.right, lessThanOrEqualTo(1192));
            }
            await tester.tap(find.text('Recent archive'));
            await tester.pumpAndSettle();
            expect(invoked, isTrue);
            expect(find.text('File'), findsNothing);
            expect(find.text('Recent'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
}
