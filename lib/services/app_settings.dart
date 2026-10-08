import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode, Locale, WidgetsBinding;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/browsing_preferences.dart';
import '../models/archive_preferences.dart';
import '../models/app_language.dart';
import '../models/selection_highlight.dart';
import '../models/theme_accent.dart';

class AppSettings extends ChangeNotifier {
  AppSettings({
    Future<int?> Function()? read,
    Future<void> Function(int)? write,
    Future<String?> Function()? readLanguage,
    Future<void> Function(String)? writeLanguage,
    Future<String?> Function()? readTheme,
    Future<void> Function(String)? writeTheme,
    Future<String?> Function()? readAccent,
    Future<void> Function(String)? writeAccent,
    Future<String?> Function()? readDpiScale,
    Future<void> Function(String)? writeDpiScale,
    Future<String?> Function()? readHighlight,
    Future<void> Function(String)? writeHighlight,
    Future<String?> Function()? readArchive,
    Future<void> Function(String)? writeArchive,
    Future<String?> Function()? readBrowsing,
    Future<void> Function(String)? writeBrowsing,
  }) : _readAccent =
           readAccent ??
           (() => SharedPreferencesAsync().getString('appearance.accent')),
       _writeAccent =
           writeAccent ??
           ((value) =>
               SharedPreferencesAsync().setString('appearance.accent', value)),
       _readLanguage =
           readLanguage ??
           (() => SharedPreferencesAsync().getString('appearance.language')),
       _writeLanguage =
           writeLanguage ??
           ((value) => SharedPreferencesAsync().setString(
             'appearance.language',
             value,
           )),
       _readArchive =
           readArchive ??
           (() => SharedPreferencesAsync().getString('archive.preferences')),
       _writeArchive =
           writeArchive ??
           ((value) => SharedPreferencesAsync().setString(
             'archive.preferences',
             value,
           )),
       _read = read ?? (() => SharedPreferencesAsync().getInt(_key)),
       _readTheme =
           readTheme ??
           (() => SharedPreferencesAsync().getString('appearance.theme')),
       _writeTheme =
           writeTheme ??
           ((value) =>
               SharedPreferencesAsync().setString('appearance.theme', value)),
       _readDpiScale =
           readDpiScale ??
           (() => SharedPreferencesAsync().getString('appearance.dpiScale')),
       _writeDpiScale =
           writeDpiScale ??
           ((value) => SharedPreferencesAsync().setString(
             'appearance.dpiScale',
             value,
           )),
       _readHighlight =
           readHighlight ??
           (() => SharedPreferencesAsync().getString(
             'appearance.fileSelectionHighlight',
           )),
       _writeHighlight =
           writeHighlight ??
           ((value) => SharedPreferencesAsync().setString(
             'appearance.fileSelectionHighlight',
             value,
           )),
       _readBrowsing =
           readBrowsing ??
           (() => SharedPreferencesAsync().getString('browsing.preferences')),
       _writeBrowsing =
           writeBrowsing ??
           ((value) => SharedPreferencesAsync().setString(
             'browsing.preferences',
             value,
           )),
       _write =
           write ?? ((value) => SharedPreferencesAsync().setInt(_key, value));
  final Future<String?> Function() _readArchive;
  final Future<void> Function(String) _writeArchive;
  ArchivePreferences archive = const ArchivePreferences();
  Future<void> setArchive(ArchivePreferences value) async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _writeArchive(jsonEncode(value.toJson()));
      archive = value;
    } catch (_) {
      error = '压缩包设置保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  final Future<String?> Function() _readLanguage;
  final Future<void> Function(String) _writeLanguage;
  AppLanguage language = AppLanguage.simplifiedChinese;
  Locale get locale =>
      language.resolve(WidgetsBinding.instance.platformDispatcher.locale);
  void synchronizeLanguage(String value) {
    final resolved = AppLanguage.values.firstWhere(
      (language) => language.name == value,
      orElse: () => AppLanguage.simplifiedChinese,
    );
    if (language == resolved) return;
    language = resolved;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (saving || value == language) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _writeLanguage(value.name);
      language = value;
    } catch (_) {
      error = '语言设置保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  static final instance = AppSettings();
  final Future<String?> Function() _readAccent;
  final Future<void> Function(String) _writeAccent;
  ThemeAccent accent = ThemeAccent.blue;

  void synchronizeAccent(String value) {
    final next = ThemeAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => ThemeAccent.blue,
    );
    if (accent == next) return;
    accent = next;
    notifyListeners();
  }

  Future<void> setAccent(ThemeAccent value) async {
    if (saving || value == accent) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _writeAccent(value.name);
      accent = value;
      selectionHighlight = SelectionHighlight.blue;
    } catch (_) {
      error = '主题色保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  static const _key = 'performance.extractionWorkers';
  final Future<int?> Function() _read;
  final Future<void> Function(int) _write;
  final Future<String?> Function() _readTheme;
  final Future<void> Function(String) _writeTheme;
  final Future<String?> Function() _readDpiScale;
  final Future<void> Function(String) _writeDpiScale;
  double dpiScale = 1;
  final Future<String?> Function() _readHighlight;
  final Future<void> Function(String) _writeHighlight;
  SelectionHighlight selectionHighlight = SelectionHighlight.blue;
  final Future<String?> Function() _readBrowsing;
  final Future<void> Function(String) _writeBrowsing;
  BrowsingPreferences browsing = const BrowsingPreferences();
  Future<void>? _browsingWrite;
  bool _browsingDirty = false;

  Future<void> setBrowsing(BrowsingPreferences value) {
    if (jsonEncode(browsing.toJson()) == jsonEncode(value.toJson())) {
      return _browsingWrite ?? Future.value();
    }
    browsing = value;
    _browsingDirty = true;
    return _browsingWrite ??= Future<void>.microtask(_flushBrowsing);
  }

  Future<void> _flushBrowsing() async {
    try {
      while (_browsingDirty) {
        _browsingDirty = false;
        try {
          await _writeBrowsing(jsonEncode(browsing.toJson()));
        } catch (_) {
          error = '浏览习惯保存失败，请重试。';
          notifyListeners();
        }
      }
    } finally {
      _browsingWrite = null;
    }
  }

  ThemeMode themeMode = ThemeMode.system;
  void synchronizeTheme(String mode) {
    final value = ThemeMode.values.firstWhere(
      (value) => value.name == mode,
      orElse: () => ThemeMode.system,
    );
    if (themeMode == value) return;
    themeMode = value;
    notifyListeners();
  }

  int? extractionWorkers;
  bool saving = false;
  String? error;

  Future<void> load() async {
    try {
      final stored = await _readAccent();
      accent = ThemeAccent.values.firstWhere(
        (value) => value.name == stored,
        orElse: () => ThemeAccent.blue,
      );
    } catch (_) {}
    try {
      final stored = await _readLanguage();
      language = AppLanguage.values.firstWhere(
        (value) => value.name == stored,
        orElse: () => AppLanguage.simplifiedChinese,
      );
    } catch (_) {
      /* Preserve the current language when storage is unavailable. */
    }

    try {
      final stored = await _readArchive();
      if (stored != null) {
        archive = ArchivePreferences.fromJson(
          Map<String, dynamic>.from(jsonDecode(stored) as Map),
        );
      }
    } catch (_) {
      /* Keep safe defaults when storage is unavailable. */
    }

    try {
      final highlight = await _readHighlight();
      selectionHighlight = SelectionHighlight.values.firstWhere(
        (value) => value.name == highlight,
        orElse: () => SelectionHighlight.blue,
      );
      if (highlight == SelectionHighlight.neutral.name) {
        selectionHighlight = SelectionHighlight.blue;
      }
    } catch (_) {
      /* Preserve appearance if storage is unavailable. */
    }
    final beforeRead = browsing;
    try {
      final stored = await _readBrowsing();
      if (stored != null &&
          _browsingWrite == null &&
          identical(browsing, beforeRead)) {
        browsing = BrowsingPreferences.fromJson(
          Map<String, dynamic>.from(jsonDecode(stored) as Map),
        );
      }
    } catch (_) {
      /* Keep the current layout if preferences cannot be read. */
    }
    try {
      final value = await _read();
      extractionWorkers = [1, 2, 4].contains(value) ? value : null;
      try {
        final theme = await _readTheme();
        themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == theme,
          orElse: () => ThemeMode.system,
        );
      } catch (_) {
        /* Default appearance when preferences are unavailable. */
      }
      try {
        final storedDpi = double.tryParse(await _readDpiScale() ?? '');
        if (storedDpi != null && storedDpi.isFinite) {
          dpiScale = storedDpi.clamp(.75, 1.5);
        }
      } catch (_) {
        /* Default DPI when preferences are unavailable. */
      }
    } catch (_) {
      // A preference read failure must not prevent opening archives.
      error = '无法读取设置，当前使用自动线程数。';
    }
    notifyListeners();
  }

  Future<void> setSelectionHighlight(SelectionHighlight value) async {
    if (saving || value == selectionHighlight) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _writeHighlight(value.name);
      selectionHighlight = value;
    } catch (_) {
      error = '文件高亮设置保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _writeTheme(mode.name);
      themeMode = mode;
    } catch (_) {
      error = '外观设置保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> setDpiScale(double value) async {
    final next = value.clamp(.75, 1.5).toDouble();
    if (saving || (dpiScale - next).abs() < .001) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _writeDpiScale(next.toStringAsFixed(2));
      dpiScale = next;
    } catch (_) {
      error = 'DPI 设置保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> setExtractionWorkers(int? value) async {
    if (![null, 1, 2, 4].contains(value)) throw ArgumentError.value(value);
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _write(value ?? 0);
      extractionWorkers = value;
    } catch (_) {
      error = '设置保存失败，请重试。';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
