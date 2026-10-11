import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Looping animations such as the attention-pulsing status bar never settle,
/// so tests run with the system "reduce motion" setting unless a test opts out.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await testMain();
}
