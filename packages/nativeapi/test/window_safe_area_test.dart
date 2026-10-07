import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart'
    show
        NativeWindowInsets,
        NativeWindowSafeArea,
        NativeSafeArea,
        NativePlatform;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = NativeWindowInsets(
    ready: true,
    padding: EdgeInsets.fromLTRB(0, 48, 0, 56),
    status: 1,
  );
  test('full screen uses physical native overlap once', () {
    final data = MediaQueryData(
      devicePixelRatio: 2,
      padding: const EdgeInsets.only(bottom: 28),
      viewPadding: const EdgeInsets.only(bottom: 28),
    );
    final safe = NativeWindowSafeArea.mediaQuery(data, native);
    expect(safe.padding, const EdgeInsets.only(top: 24, bottom: 28));
  });
  test('restoring decorated window clears stale full screen padding', () {
    final data = MediaQueryData(
      devicePixelRatio: 2,
      padding: const EdgeInsets.only(top: 24, bottom: 28),
      viewPadding: const EdgeInsets.only(top: 24, bottom: 28),
    );
    const window = NativeWindowInsets(
      ready: true,
      padding: EdgeInsets.zero,
      status: 4,
    );
    expect(
      NativeWindowSafeArea.mediaQuery(data, window).padding,
      EdgeInsets.zero,
    );
  });
  test('keyboard consumes bottom padding but preserves viewPadding', () {
    const data = MediaQueryData(
      devicePixelRatio: 2,
      viewInsets: EdgeInsets.only(bottom: 300),
    );
    final safe = NativeWindowSafeArea.mediaQuery(data, native);
    expect(safe.padding.bottom, 0);
    expect(safe.viewPadding.bottom, 28);
    expect(safe.viewInsets.bottom, 300);
  });
  test('unavailable native metrics preserve engine safe area', () {
    const data = MediaQueryData(padding: EdgeInsets.only(top: 32));
    const missing = NativeWindowInsets(
      ready: false,
      padding: EdgeInsets.zero,
      status: 0,
    );
    expect(NativeWindowSafeArea.mediaQuery(data, missing), same(data));
    expect(NativeWindowSafeArea.mediaQuery(data, null), same(data));
  });
  testWidgets(
    'Android phone and pad avoid system bars without double padding',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final size in [const Size(400, 800), const Size(1000, 800)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: const EdgeInsets.only(top: 32, bottom: 24),
                viewPadding: const EdgeInsets.only(top: 32, bottom: 24),
              ),
              child: NativeSafeArea(
                backgroundColor: Colors.grey,
                child: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(
                        key: ValueKey('toolbar'),
                        height: 48,
                        width: double.infinity,
                      ),
                      const Spacer(),
                      const SizedBox(
                        key: ValueKey('footer'),
                        height: 28,
                        width: double.infinity,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.getTopLeft(find.byKey(const ValueKey('toolbar'))).dy, 32);
        expect(
          tester.getBottomRight(find.byKey(const ValueKey('footer'))).dy,
          size.height - 24,
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'pad content fills left and bottom without nested safe-area padding',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(1000, 800),
              padding: EdgeInsets.fromLTRB(32, 48, 0, 28),
              viewPadding: EdgeInsets.fromLTRB(32, 48, 0, 28),
            ),
            child: NativeSafeArea(
              left: false,
              bottom: false,
              backgroundColor: Colors.grey,
              child: SafeArea(
                child: SizedBox.expand(key: ValueKey('edge-content')),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('edge-content'))),
        const Offset(0, 48),
      );
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('edge-content'))),
        const Offset(1000, 800),
      );
    },
  );
  final ohos = TargetPlatform.values.where((p) => p.name == 'ohos');
  testWidgets(
    'HarmonyOS updates safe area while switching window states',
    (tester) async {
      debugDefaultTargetPlatformOverride = ohos.single;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const events = 'nativeapi/hizip/windowInsets';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        NativePlatform.channel,
        (_) async => {
          'ready': true,
          'top': 48,
          'bottom': 56,
          'left': 0,
          'right': 0,
          'status': 1,
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel(events),
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(NativePlatform.channel, null);
        messenger.setMockMethodCallHandler(const MethodChannel(events), null);
      });
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(size: Size(1000, 800)),
            child: NativeSafeArea(
              backgroundColor: Colors.grey,
              child: SizedBox.expand(key: ValueKey('content')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('content'))).dy, 48);
      await messenger.handlePlatformMessage(
        events,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'ready': true,
          'top': 0,
          'bottom': 0,
          'left': 0,
          'right': 0,
          'status': 4,
        }),
        (_) {},
      );
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('content'))).dy, 0);
      expect(tester.getSize(find.byKey(const ValueKey('content'))).height, 800);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
    skip: ohos.isEmpty,
  );
}
