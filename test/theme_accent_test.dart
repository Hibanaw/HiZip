import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/theme_accent.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/ui/desktop_widgets.dart';

void main() {
  test('theme accent persists and invalid values fall back to blue', () async {
    String? stored;
    AppSettings create() => AppSettings(
      read: () async => null,
      readAccent: () async => stored,
      writeAccent: (value) async => stored = value,
    );
    final first = create();
    final second = create();
    await first.setAccent(ThemeAccent.teal);
    await second.load();
    expect(second.accent, ThemeAccent.teal);
    stored = 'invalid';
    await second.load();
    expect(second.accent, ThemeAccent.blue);
    first.dispose();
    second.dispose();
  });

  test('failed accent save retains current color', () async {
    final settings = AppSettings(
      writeAccent: (_) async => throw StateError('disk'),
    );
    await settings.setAccent(ThemeAccent.rose);
    expect(settings.accent, ThemeAccent.blue);
    expect(settings.error, isNotNull);
    settings.dispose();
  });

  test('loading accent notifies even when another preference fails', () async {
    final settings = AppSettings(
      read: () async => throw StateError('disk'),
      readAccent: () async => 'teal',
    );
    var notifications = 0;
    settings.addListener(() => notifications++);
    await settings.load();
    expect(settings.accent, ThemeAccent.teal);
    expect(notifications, 1);
    settings.dispose();
  });

  for (final accent in ThemeAccent.values) {
    for (final brightness in Brightness.values) {
      test('${accent.name} remains readable in $brightness', () {
        final theme = desktopTheme(brightness: brightness, accent: accent);
        final foreground = theme.colorScheme.onPrimary.computeLuminance() + .05;
        final background = theme.colorScheme.primary.computeLuminance() + .05;
        expect(foreground / background, greaterThanOrEqualTo(4.5));
        expect(theme.colorScheme.primary, accent.color);
      });
    }
  }
}
