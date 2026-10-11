import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nativeapi/nativeapi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('System folders use a decodable folder image, not a document', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<Uint8List> icon(String name, bool directory) async =>
          (await NativePlatform.channel.invokeMethod<Uint8List>('fileIcon', {
            'path': name,
            'directory': directory,
          }))!;
      final folder = await icon('中文 文件夹', true);
      final document = await icon('unknown.hizipunknown', false);
      expect(folder, isNotEmpty);
      expect(folder, isNot(orderedEquals(document)));
      // A directory with a file suffix must still use the folder resource.
      expect(await icon('文件夹.zip', true), orderedEquals(folder));
      for (final bytes in [
        folder,
        document,
        await icon('archive.zip', false),
      ]) {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, greaterThan(0));
            expect(frame.image.height, greaterThan(0));
            expect(await frame.image.toByteData(), isNotNull);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    });
  });
}
