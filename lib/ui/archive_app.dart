import 'app_localizations.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/archive_entry.dart';
import '../models/browsing_preferences.dart';
import '../models/archive_index.dart';
import '../models/directory_listing.dart';
import '../models/preview_text.dart';
import '../models/preview_limit.dart';
import '../services/archive_service.dart';
import '../services/desktop_integration.dart';
import 'file_item_surface.dart';
import 'gallery_browser.dart';
import 'file_context_menu.dart';
import '../models/archive_preferences.dart';
import '../models/archive_formats.dart';
import 'desktop_widgets.dart';
import 'settings_page.dart';
import '../services/app_settings.dart';
import '../services/task_windows.dart';
import 'window_chrome.dart';
import 'task_feedback_controller.dart';
import '../services/archive_task_queue.dart';
import '../services/queued_archive_service.dart';
import '../models/task_feedback.dart';
import 'file_drop_target.dart';
import 'touch_file_drop_target.dart';
import '../services/file_transfer_clipboard.dart';

import 'package:super_drag_and_drop/super_drag_and_drop.dart';

const muted = Color(0xff8b909b), blue = Color(0xff3478f6);

class _ArchiveTab {
  _ArchiveTab(this.document);
  ArchiveDocument document;
  String folder = '', query = '', status = '';
  List<String> history = [];
  Set<String> expanded = {''}, selection = {};
  Set<(String, String)> expandedListings = {};
  ArchiveEntry? selected;
  Uint8List? preview;
  String? previewText, previewError;
  double listOffset = 0, columnOffset = 0;
  Map<String, double> columnOffsets = {};
  int revision = 0, cachedRevision = -1;
  ArchiveFolder? cachedTree;
  List<(ArchiveFolder, int)> rows = [];
}

class ArchiveWorkspace extends StatefulWidget {
  const ArchiveWorkspace({
    super.key,
    this.service,
    this.settings,
    this.desktop,
    this.initialDocument,
    this.clipboard,
    this.enableNativeTransfers = true,
  });
  final FileTransferClipboard? clipboard;
  final bool enableNativeTransfers;
  final AppSettings? settings;
  final ArchiveService? service;
  final DesktopIntegration? desktop;
  final ArchiveDocument? initialDocument;
  @override
  State<ArchiveWorkspace> createState() => _ArchiveWorkspaceState();
}

class _ArchiveWorkspaceState extends State<ArchiveWorkspace>
    with WidgetsBindingObserver {
  static const listInset = 6.0;
  final contentScaffold = GlobalKey<ScaffoldState>();
  late final settings = widget.settings ?? AppSettings.instance;
  final taskQueue = ArchiveTaskQueue();
  late final service = QueuedArchiveService(
    widget.service ?? ArchiveService(),
    taskQueue,
  );
  bool queueExpanded = false;
  TextEditingController? entryNameInput;
  int runningOperations = 0;
  late final desktop = widget.desktop ?? DesktopIntegration();
  late final clipboard = widget.clipboard ?? FileTransferClipboard();
  final selectedPaths = <String>{};
  final expandedListings = <(String, String)>{};
  final transferExports = <String, Future<List<String>>>{};
  final fileFocus = FocusNode(debugLabel: 'archive files');
  final searchFocus = FocusNode(debugLabel: 'archive search');
  bool compactSearchOpen = false;
  final listScroll = ScrollController();
  final columnScroll = ScrollController();
  final pathScroll = ScrollController();
  final columnLists = <String, ScrollController>{};
  double sidebarWidth = 230, inspectorWidth = 270;
  String listSortColumn = 'name';
  bool listSortAscending = true;
  double listNameWidth = 0,
      listSizeWidth = 85,
      listModifiedWidth = 115,
      listKindWidth = 85;
  bool columns = false, gallery = false, inspectorVisible = false;
  final expandedFolders = <String>{''};
  ArchiveFolder folderTree = ArchiveFolder('');
  DefaultApplication? selectedApplication;
  int systemPreviewRequest = 0, gridColumns = 1;
  double gridTileExtent = 0, gridPadding = 0, gridSpacing = 0;
  double listIconSize = 22,
      gridIconSize = 64,
      columnIconSize = 20,
      galleryIconSize = 80;
  String get browsingView => gallery
      ? 'gallery'
      : columns
      ? 'columns'
      : grid
      ? 'grid'
      : 'list';
  double get iconSize => gallery
      ? galleryIconSize
      : columns
      ? columnIconSize
      : grid
      ? gridIconSize
      : listIconSize;
  set iconSize(double value) {
    if (gallery) {
      galleryIconSize = value;
    } else if (columns) {
      columnIconSize = value;
    } else if (grid) {
      gridIconSize = value;
    } else {
      listIconSize = value;
    }
  }

  double rowExtent(double size) {
    final textHeight = MediaQuery.textScalerOf(context).scale(12) * 1.3;
    return (size > textHeight ? size : textHeight) +
        2 * (size * .16).clamp(2.0, 6.0);
  }

  bool openingSystemPreview = false;
  (ArchiveDocument, List<ArchiveEntry>)? activeDrag, armedDrag;
  (ArchiveDocument, List<ArchiveEntry>)? touchDrag;
  final touchDrops = TouchFileDropController();
  final search = TextEditingController();
  final recent = <String>[];
  final tabs = <_ArchiveTab>[];
  List<(_ArchiveTab, ArchiveFolder, int)> sidebarSources = [];
  List<(_ArchiveTab, ArchiveFolder, int)> sidebarRows = [];
  final sidebarScroll = ScrollController();
  final tabScroll = ScrollController();
  Future<void> openQueue = Future.value();
  bool restoringTab = false;
  final history = <String>[];
  ArchiveDocument? document;
  ArchiveEntry? selected;
  String folder = '', status = '未打开压缩包';
  bool statusError = false;
  Timer? statusResetTimer;
  bool busy = false,
      grid = false,
      inspector = true,
      checking = false,
      prompting = false;
  bool pointerSelectedItem = false, closing = false;
  Completer<void>? operationDone;
  double? progress;
  Uint8List? preview;
  String? previewText;
  Timer? searchTimer, warmTimer;
  int searchRequest = 0;
  List<ArchiveEntry>? searchResults;
  String? searchedFolder, searchedTerm;
  ArchiveDocument? searchedDocument;
  int sidebarRevision = 0;
  String? previewError;
  int previewRequest = 0;
  int dragPreparationRequest = 0;
  Timer? timer;
  final pending = <OpenedArchiveFile>[];
  Color get ink => Theme.of(context).colorScheme.onSurface;
  final feedback = TaskFeedbackController(
    useNativeWindows: false,
    progressDelay: Duration.zero,
  );
  @override
  void initState() {
    super.initState();
    final browsing = settings.browsing;
    grid = browsing.view == 'grid';
    columns = browsing.view == 'columns';
    gallery = browsing.view == 'gallery';
    listIconSize = browsing.listIconSize;
    gridIconSize = browsing.gridIconSize;
    columnIconSize = browsing.columnIconSize;
    galleryIconSize = browsing.galleryIconSize;
    inspector = browsing.inspector;
    sidebarWidth = browsing.sidebarWidth;
    inspectorWidth = browsing.inspectorWidth;
    listSortColumn = browsing.listSortColumn;
    listSortAscending = browsing.listSortAscending;
    listNameWidth = browsing.listNameWidth;
    listSizeWidth = browsing.listSizeWidth;
    listModifiedWidth = browsing.listModifiedWidth;
    listKindWidth = browsing.listKindWidth;
    applySettings();
    settings.addListener(applySettings);
    taskQueue.addListener(queueChanged);
    document = widget.initialDocument;
    if (document != null) {
      folderTree = document!.index.tree;
      recent.add(document!.path);
      tabs.add(_ArchiveTab(document!));
      status = '${document!.entries.length} 个项目';
    }
    desktop.listen(
      navigate: (delta) => moveSelection(delta, fromQuickLook: true),
      prepareClose: prepareToClose,
      dragEnded: () {
        final drag = activeDrag;
        activeDrag = null;
        if (mounted && drag != null && !busy && !closing) {
          message(
            desktop.lastDragSucceeded == false
                ? '拖拽已取消'
                : '拖拽完成：${drag.$2.length} 个项目',
          );
        }
      },
      dragStarted: () {
        activeDrag = armedDrag;
        feedback.action('dismiss');
      },
      command: handleMenuCommand,
      openArchive: loadArchive,
      clearRecent: () => setState(recent.clear),
    );
    unawaited(initializeArchives());
    fileFocus.addListener(syncFileCommands);
    searchFocus.addListener(syncFileCommands);
    WidgetsBinding.instance.addObserver(this);
    search.addListener(() {
      if (restoringTab) return;
      clearPreparedDrag();
      final term = search.text.toLowerCase();
      selectedPaths.removeWhere(
        (path) =>
            !(document?.index.byPath[path]?.name.toLowerCase().contains(term) ??
                false),
      );
      if (selected != null && !selectedPaths.contains(selected!.path)) {
        selected = null;
        ++previewRequest;
        preview = null;
        previewText = null;
      }
      searchTimer?.cancel();
      final request = ++searchRequest;
      searchResults = null;
      setState(() {});
      if (search.text.isNotEmpty) {
        searchTimer = Timer(
          const Duration(milliseconds: 140),
          () => searchFolder(request),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ensureGallerySelection(),
    );
    timer = Timer.periodic(const Duration(seconds: 3), (_) => checkChanges());
  }

  @override
  void dispose() {
    settings.removeListener(applySettings);
    feedback.dispose();
    touchDrops.dispose();
    taskQueue.removeListener(queueChanged);
    timer?.cancel();
    statusResetTimer?.cancel();
    searchTimer?.cancel();
    warmTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(desktop.enableFileCommands(false));
    desktop.dispose();
    fileFocus.dispose();
    searchFocus.dispose();
    sidebarScroll.dispose();
    tabScroll.dispose();
    listScroll.dispose();
    columnScroll.dispose();
    pathScroll.dispose();
    for (final controller in columnLists.values) {
      controller.dispose();
    }
    search.dispose();
    unawaited(service.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkChanges();
  }

  @override
  void didChangeLocales(List<Locale>? locales) => applySettings();

  void applySettings() {
    unawaited(desktop.setLanguage(settings.locale.languageCode));
    service.maxExtractionWorkers = settings.extractionWorkers;
    service.readEncoding = settings.archive.readEncoding;
    service.createEncoding = settings.archive.createEncoding;
    service.compressionLevel = settings.archive.compressionLevel;
    unawaited(desktop.setAppearance(settings.themeMode.name));
    if (mounted) setState(() {});
  }

  void saveBrowsingPreferences() => unawaited(
    settings.setBrowsing(
      BrowsingPreferences(
        view: browsingView,
        listIconSize: listIconSize,
        gridIconSize: gridIconSize,
        columnIconSize: columnIconSize,
        galleryIconSize: galleryIconSize,
        inspector: inspector,
        sidebarWidth: sidebarWidth,
        inspectorWidth: inspectorWidth,
        listSortColumn: listSortColumn,
        listSortAscending: listSortAscending,
        listNameWidth: listNameWidth,
        listSizeWidth: listSizeWidth,
        listModifiedWidth: listModifiedWidth,
        listKindWidth: listKindWidth,
      ),
    ),
  );

  void sortList(String column) {
    setState(() {
      if (listSortColumn == column) {
        listSortAscending = !listSortAscending;
      } else {
        listSortColumn = column;
        listSortAscending = true;
      }
    });
    saveBrowsingPreferences();
  }

  void resizeListColumn(String column, double delta, {double? currentWidth}) {
    setState(() {
      switch (column) {
        case 'name':
          listNameWidth =
              (listNameWidth == 0 ? currentWidth ?? 260 : listNameWidth) +
              delta;
          break;
        case 'size':
          listSizeWidth = (listSizeWidth + delta).clamp(65.0, 400.0);
          break;
        case 'modified':
          listModifiedWidth = (listModifiedWidth + delta).clamp(90.0, 400.0);
          break;
        case 'kind':
          listKindWidth = (listKindWidth + delta).clamp(65.0, 300.0);
          break;
      }
      if (column == 'name') listNameWidth = listNameWidth.clamp(160.0, 2000.0);
    });
  }

  double listColumnWidth(String column, double fallback) => switch (column) {
    'name' => listNameWidth == 0 ? fallback : listNameWidth,
    'size' => listSizeWidth,
    'modified' => listModifiedWidth,
    'kind' => listKindWidth,
    _ => fallback,
  };

  void changeView(String view) {
    setState(() {
      grid = view == 'grid';
      columns = view == 'columns';
      gallery = view == 'gallery';
    });
    saveBrowsingPreferences();
    if (columns) revealColumns();
    if (gallery) {
      if (selected != null) {
        unawaited(
          select(selected!, forcePreview: true, preserveSelection: true),
        );
      } else {
        ensureGallerySelection();
      }
    }
  }

  void ensureGallerySelection() {
    if (mounted &&
        gallery &&
        document != null &&
        selected == null &&
        visibleItems.isNotEmpty) {
      unawaited(select(visibleItems.first));
    }
  }

  void toggleInspector() {
    setState(() => inspector = !inspector);
    saveBrowsingPreferences();
    if (inspector && selected != null) select(selected!);
  }

  void handleMenuCommand(String command) {
    if (command == 'copy') copyFiles();
    if (command == 'paste') pasteFiles();
    if (command == 'selectAll') selectAllFiles();
    if (command == 'settings') openSettings();
    if (command == 'open') pickArchive();
    if (command == 'create') createArchive();
    if (command.startsWith('create:')) {
      createArchive(format: command.substring(7));
    }
    if (command == 'closeArchive') closeTab(document?.path);
    if (command == 'extract') extract();
    if (command == 'newFolder') newEntry(directory: true);
    if (command == 'newDocument') newEntry();
    if (command == 'delete') deleteSelection();
    if (command == 'list' ||
        command == 'grid' ||
        command == 'columns' ||
        command == 'gallery') {
      changeView(command);
    }
    if (command.startsWith('encoding:') && document != null) {
      final encoding = command.substring(9);
      if (archiveEncodings.containsKey(encoding)) {
        loadArchive(document!.path, encoding: encoding);
      }
    }
    if (command == 'inspector') toggleInspector();
  }

  Future<void> initializeArchives() async {
    await loadRecentArchives();
    final paths = await desktop.initialArchivePaths();
    for (final path in paths) {
      if (!mounted || closing) return;
      await loadArchive(path);
    }
  }

  Future<void> loadRecentArchives() async {
    final paths = await desktop.initializeMenus();
    if (!mounted) return;
    setState(() {
      for (final path in paths) {
        if (!recent.contains(path)) recent.add(path);
      }
    });
  }

  Future<void> openSettings() async {
    try {
      if (await showSettingsWindow(settings)) return;
    } catch (e) {
      message('$e', error: true);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => SettingsPage(settings: settings),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (mounted) fileFocus.requestFocus();
  }

  void queueChanged() {
    if (mounted) setState(() {});
  }

  Future<void> run(
    Future<void> Function() work, {
    String title = '正在处理文件',
    bool showProgress = true,
    bool reportSuccess = true,
    String? archivePath,
  }) async {
    if (closing || !mounted) return;
    await taskQueue.run(archivePath ?? document?.path ?? "", title, () async {
      if (!mounted || closing) return;
      while (feedback.reply != null) {
        await feedback.reply!.future;
        if (!mounted || closing) return;
      }
      final done = operationDone = Completer<void>();
      clearPreparedDrag();
      final feedbackToken = feedback.begin(
        title,
        showProgress: showProgress,
        reportFastSuccess: reportSuccess,
      );
      setState(() {
        runningOperations++;
        busy = true;
        progress = null;
        statusError = false;
      });
      try {
        await work();
      } catch (e) {
        if (mounted) {
          message(e.toString().replaceFirst('Bad state: ', ''), error: true);
        }
      } finally {
        feedback.finish(token: feedbackToken);
        if (!done.isCompleted) done.complete();
        if (identical(operationDone, done)) operationDone = null;
        if (mounted) {
          setState(() {
            runningOperations--;
            busy = runningOperations > 0;
            progress = null;
          });
          unawaited(showChanges());
        }
      }
    });
  }

  Future<T> observed<T>(
    String title,
    Future<T> Function() work, {
    required String success,
    bool Function()? current,
    bool reportFastSuccess = true,
  }) async {
    if (closing || !mounted) throw StateError('操作已取消');
    return taskQueue.run(document?.path ?? '', title, () async {
      if (closing || !mounted || current?.call() == false) {
        throw StateError('操作已取消');
      }
      if (busy) return work();
      final token = feedback.begin(
        title,
        reportFastSuccess: reportFastSuccess,
        current: () => mounted && (current?.call() ?? true),
      );
      try {
        final result = await work();
        if (mounted && (current?.call() ?? true)) {
          feedback.result(success, token: token);
        } else if (token == feedback.generation) {
          feedback.action('dismiss');
        }
        return result;
      } catch (error) {
        if (error is PreviewLimitExceeded) {
          if (token == feedback.generation) feedback.action('dismiss');
        } else if (mounted && (current?.call() ?? true)) {
          feedback.result(
            error.toString().replaceFirst('Bad state: ', ''),
            error: true,
            token: token,
          );
        } else if (token == feedback.generation) {
          feedback.action('dismiss');
        }
        rethrow;
      } finally {
        feedback.finish(token: token);
      }
    });
  }

  Future<void> prepareToClose() async {
    closing = true;
    try {
      warmTimer?.cancel();
      ++previewRequest;
      ++systemPreviewRequest;
      feedback.action('dismiss');
      await taskQueue.drain();
      await desktop.closeQuickLook();
      await service.dispose();
      timer?.cancel();
      pending.clear();
      transferExports.clear();
    } catch (error) {
      closing = false;
      message('临时缓存清理失败，请重试关闭窗口：$error', error: true);
      rethrow;
    }
  }

  void message(String text, {bool error = false, bool showFeedback = true}) {
    if (mounted) {
      statusResetTimer?.cancel();
      if (showFeedback) feedback.result(text, error: error);
      setState(() {
        status = text;
        statusError = error;
      });
      if (!error) {
        statusResetTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          feedback.action('dismiss');
          setState(() {
            status = defaultStatus();
            statusError = false;
          });
        });
      }
    }
  }

  String defaultStatus() {
    final doc = document;
    if (doc == null) return '未打开压缩包';
    final count = itemsInFolder(folder).length;
    final selectedCount = selection.length;
    return selectedCount == 0
        ? '$count 个项目'
        : '$count 个项目 · 已选择 $selectedCount 个项目';
  }

  Future<void> pickArchive() async {
    if (!service.supported) {
      message('浏览器版本需要 WebAssembly 引擎。请使用原生桌面版本。');
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '压缩文件',
          extensions: readableArchiveExtensions,
          uniformTypeIdentifiers: ['public.data'],
        ),
      ],
    );
    for (final file in files) {
      await loadArchive(file.path);
    }
  }

  _ArchiveTab? tabFor(String? path) {
    for (final tab in tabs) {
      if (tab.document.path == path) return tab;
    }
    return null;
  }

  void saveActiveTab() {
    final tab = tabFor(document?.path);
    if (tab == null) return;
    tab.document = document!;
    tab.folder = folder;
    tab.query = search.text;
    tab.status = status;
    tab.history = List.of(history);
    tab.expanded = Set.of(expandedFolders);
    tab.selection = Set.of(selectedPaths);
    tab.expandedListings = Set.of(expandedListings);
    tab.selected = selected;
    tab.preview = preview;
    tab.previewText = previewText;
    tab.previewError = previewError;
    tab.listOffset = listScroll.hasClients ? listScroll.offset : 0;
    tab.columnOffset = columnScroll.hasClients ? columnScroll.offset : 0;
    tab.columnOffsets = {
      for (final entry in columnLists.entries)
        entry.key: entry.value.hasClients ? entry.value.offset : 0,
    };
  }

  void focusSidebar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !sidebarScroll.hasClients) return;
      var row = 0;
      for (final tab in tabs) {
        for (final item in tab.rows) {
          if (tab.document.path == document?.path && item.$1.path == folder) {
            final target = listInset + row * 29.0;
            final position = sidebarScroll.position;
            if (target < position.pixels ||
                target + 29 > position.pixels + position.viewportDimension) {
              sidebarScroll.jumpTo(target.clamp(0, position.maxScrollExtent));
            }
            return;
          }
          row++;
        }
      }
    });
  }

  void activateTab(_ArchiveTab? tab, {bool save = true}) {
    if (save) saveActiveTab();
    clearPreparedDrag();
    transferExports.clear();
    warmTimer?.cancel();
    searchTimer?.cancel();
    ++previewRequest;
    ++systemPreviewRequest;
    ++searchRequest;
    unawaited(desktop.closeQuickLook());
    restoringTab = true;
    setState(() {
      document = tab?.document;
      folderTree = document?.index.tree ?? ArchiveFolder('');
      folder = tab?.folder ?? '';
      history
        ..clear()
        ..addAll(tab?.history ?? []);
      expandedFolders
        ..clear()
        ..addAll(tab?.expanded ?? {''});
      expandedListings
        ..clear()
        ..addAll(tab?.expandedListings ?? {});
      ++sidebarRevision;
      selected = tab?.selected;
      selectedPaths
        ..clear()
        ..addAll(tab?.selection ?? {});
      preview = tab?.preview;
      previewText = tab?.previewText;
      previewError = tab?.previewError;
      selectedApplication = null;
      search.text = tab?.query ?? '';
      searchResults = null;
      searchedDocument = null;
      searchedFolder = searchedTerm = null;
      status = tab == null
          ? '未打开压缩包'
          : tab.status.isEmpty
          ? defaultStatus()
          : tab.status;
      statusError = false;
    });
    restoringTab = false;
    if (search.text.isNotEmpty) unawaited(searchFolder(searchRequest));
    if (selected != null) {
      unawaited(updateApplication(selected!, previewRequest));
      if (preview == null && (inspector || gallery)) {
        unawaited(select(selected!, preserveSelection: true));
      }
    }
    ensureGallerySelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || document != tab?.document) return;
      void restore(ScrollController controller, double offset) {
        if (controller.hasClients) {
          controller.jumpTo(
            offset.clamp(0, controller.position.maxScrollExtent),
          );
        }
      }

      restore(listScroll, tab?.listOffset ?? 0);
      restore(columnScroll, tab?.columnOffset ?? 0);
      for (final entry in columnLists.entries) {
        restore(entry.value, tab?.columnOffsets[entry.key] ?? 0);
      }
    });
    focusSidebar();
    fileFocus.requestFocus();
  }

  void switchTab(_ArchiveTab tab) {
    if (busy || closing || document?.path == tab.document.path) return;
    activateTab(tab);
  }

  Future<void> closeTab(String? path) async {
    final tab = tabFor(path);
    if (tab == null || closing) return;
    await run(
      () async {
        if (!tabs.contains(tab)) return;
        final active = document?.path == path;
        final index = tabs.indexOf(tab);
        if (active) {
          ++previewRequest;
          ++systemPreviewRequest;
          warmTimer?.cancel();
          await desktop.closeQuickLook();
        }
        await service.closeArchive(tab.document.path);
        if (!mounted) return;
        pending.removeWhere((file) => file.archive == path);
        setState(() => tabs.remove(tab));
        if (active) {
          activateTab(
            tabs.isEmpty ? null : tabs[(index - 1).clamp(0, tabs.length - 1)],
            save: false,
          );
        } else {
          focusSidebar();
        }
        message('已关闭压缩包：${p.basename(tab.document.path)}', showFeedback: false);
      },
      title: '正在关闭压缩包',
      showProgress: false,
      reportSuccess: false,
      archivePath: tab.document.path,
    );
  }

  Future<void> loadArchive(String path, {String? encoding}) {
    final next = taskQueue.run(path, '正在打开压缩包', () async {
      if (!mounted || closing) return;
      final existing = tabFor(path);
      if (existing != null && encoding == null) {
        activateTab(existing);
        return;
      }
      await run(
        () async {
          service.readEncoding = encoding ?? settings.archive.readEncoding;
          final result = await service.read(path);
          if (!mounted) return;
          saveActiveTab();
          final previousIndex = existing == null ? -1 : tabs.indexOf(existing);
          if (existing != null) {
            await service.closeArchive(path);
            pending.removeWhere((file) => file.archive == path);
            tabs.remove(existing);
          }
          final tab = _ArchiveTab(result);
          if (existing == null) {
            tabs.add(tab);
          } else {
            tabs.insert(previousIndex, tab);
          }
          activateTab(tab, save: false);
          recent.remove(path);
          recent.insert(0, path);
          await desktop.noteRecentArchive(path);
          message('已打开压缩包：${p.basename(path)}');
        },
        title: '正在打开压缩包',
        archivePath: path,
      );
    }, after: openQueue);
    openQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> createArchive({String format = 'zip'}) async {
    if (!writableArchiveFormats.containsKey(format)) return;
    if (!service.supported) return;
    final files = await openFiles();
    if (files.isEmpty) return;
    final target = await getSaveLocation(
      suggestedName: 'Archive.$format',
      acceptedTypeGroups: [
        XTypeGroup(
          label: writableArchiveFormats[format]!,
          extensions: [format],
        ),
      ],
    );
    if (target == null) return;
    await run(
      () async {
        await service.create(target.path, files.map((f) => f.path).toList());
        message('压缩包已创建');
      },
      title: '正在创建压缩包',
      archivePath: target.path,
    );
    await loadArchive(target.path, encoding: settings.archive.createEncoding);
  }

  void navigate(String next, {bool back = false}) {
    if (next == folder) return;
    clearPreparedDrag();
    previewRequest++;
    ++systemPreviewRequest;
    unawaited(desktop.closeQuickLook());
    expandAncestors(next);
    setState(() {
      if (!back) history.add(folder);
      folder = next;
      selectedApplication = null;
      selected = null;
      selectedPaths.clear();
      preview = null;
      previewText = null;
      previewError = null;
      search.clear();
    });
    if (columns) revealColumns();
    ensureGallerySelection();
  }

  void goBack() {
    if (history.isNotEmpty) navigate(history.removeLast(), back: true);
  }

  Future<void> select(
    ArchiveEntry entry, {
    bool forcePreview = false,
    bool preserveSelection = false,
  }) async {
    final token = ++previewRequest;
    if (!entry.directory) clearPreparedDrag();
    setState(() {
      selected = entry;
      if (!preserveSelection) selectedPaths.clear();
      selectedPaths.add(entry.path);
      selectedApplication = null;
      preview = null;
      previewText = null;
      previewError = null;
      status = defaultStatus();
    });
    if (entry.directory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != previewRequest) return;
        clearPreparedDrag();
        unawaited(desktop.closeQuickLook());
      });
      return;
    }
    warmExport();
    unawaited(updateApplication(entry, token));
    unawaited(updateSystemPreview(entry, token));
    if ((!inspector && !gallery && !forcePreview) ||
        entry.directory ||
        !(entry.isImage || entry.isText)) {
      return;
    }
    try {
      if (!mounted || token != previewRequest) return;
      final (data, text) = await observed(
        '正在生成预览',
        () async {
          final data = await service.preview(document!, entry);
          final text = entry.isText
              ? (data.length <= 4096
                    ? decodePreviewText(data)
                    : await compute(
                        decodePreviewText,
                        data,
                        debugLabel: 'hizip-text-preview',
                      ))
              : null;
          return (data, text);
        },
        success: '预览已就绪：${entry.name}',
        current: () => token == previewRequest,
        reportFastSuccess: false,
      );
      if (mounted && token == previewRequest) {
        setState(() {
          preview = data;
          previewText = text;
        });
      }
    } catch (e) {
      if (mounted && token == previewRequest) {
        setState(
          () => previewError = e.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> openEntry(ArchiveEntry e, {FileApplication? application}) async {
    final doc = document;
    if (doc == null || closing) return;
    if (e.directory) {
      navigate(e.normalized);
      return;
    }
    final openInHiZip = application == null && isReadableArchivePath(e.name);
    await run(
      () async {
        if (tabFor(doc.path) == null) return;
        final f = openInHiZip
            ? await service.prepareExternal(doc, e)
            : application == null
            ? await service.open(doc, e)
            : await service.prepareExternal(doc, e);
        if (openInHiZip) {
          await loadArchive(f.path);
          return;
        }
        if (application != null) await desktop.openWith(f.path, application);
        message(
          application == null
              ? '已在默认应用中打开 · 修改检测已开启'
              : '已用 ${application.name} 打开 · 修改检测已开启',
        );
        if (!doc.writable) message('当前格式只读。修改后的文件保留在 ${f.path}');
      },
      title: '正在打开文件',
      archivePath: doc.path,
    );
  }

  Future<void> extract({bool onlySelected = false}) async {
    final doc = document;
    if (doc == null || closing) return;
    final extractionDoc = onlySelected && selection.length > 1
        ? selectedDocument()
        : doc;
    final extractionEntry = onlySelected && selection.length <= 1
        ? selected
        : null;
    final target = await getDirectoryPath(
      confirmButtonText: translateAppText(
        '解压到这里',
        settings.locale.languageCode,
      ),
    );
    if (target == null) return;
    await run(
      () async {
        if (tabFor(doc.path) == null) return;
        final output = await service.extract(
          extractionDoc,
          target,
          entry: extractionEntry,
          progress: (done, total) {
            if (mounted) {
              setState(() {
                progress = total == 0 ? 1 : done / total;
                status = '正在解压 $done / $total';
              });
            }
          },
          detailedProgress: (value) {
            feedback.update(
              '正在解压',
              detail:
                  '${value.completed} / ${value.totalFiles} 个文件 · ${p.basename(doc.path)}',
              progress: value.overall,
              fileProgress: value.current,
              currentFile: value.currentFile,
            );
          },
        );
        message('解压完成：$output');
      },
      title: '正在解压',
      archivePath: doc.path,
      showProgress: true,
    );
  }

  Future<void> checkChanges() async {
    if (checking || !mounted || closing) return;
    checking = true;
    try {
      pending.addAll(await service.changes());
      try {
        await service.updateClipboardExports(await clipboard.readFiles());
      } catch (_) {
        /* Keep a clipboard lease if the clipboard is unavailable. */
      }
      if (mounted) await showChanges();
    } catch (_) {
      /* A temporarily inaccessible editor file is retried next time. */
    } finally {
      checking = false;
    }
  }

  Future<void> showChanges() async {
    if (prompting || busy || !mounted || closing || pending.isEmpty) return;
    prompting = true;
    try {
      while (pending.isNotEmpty && mounted && !busy && !closing) {
        final file = pending.removeAt(0);
        if (!mounted) return;
        await taskQueue.run(file.archive, '等待保存确认', () async {
          if (!mounted || closing || tabFor(file.archive) == null) return;
          setState(() => busy = true);
          final action = await feedback.ask(
            TaskFeedback(
              title: '文件已修改',
              detail:
                  '“${p.posix.basename(file.entry)}” 已修改，是否更新压缩包？\n\n选择“否”不会保存修改。关闭压缩包后，未保存的内容将丢失。',
              actions: const {'discard': '否', 'save': '是'},
            ),
          );
          if (!mounted) return;
          if (action == 'save') {
            try {
              feedback.begin('正在保存回压缩包');
              setState(() => busy = true);
              await service.save(file);
              final affectedTab = tabFor(file.archive);
              if (affectedTab != null) {
                service.readEncoding = affectedTab.document.encoding;
                final updated = await service.read(file.archive);
                if (mounted) {
                  affectedTab.document = updated;
                  affectedTab.selected =
                      updated.index.byPath[affectedTab.selected?.path];
                  affectedTab.preview = null;
                  affectedTab.previewText = null;
                  affectedTab.previewError = null;
                  if (document?.path != file.archive) {
                    setState(() {});
                  } else {
                    final selectedPath = selected?.path;
                    setState(() {
                      clearPreparedDrag();
                      transferExports.clear();
                      document = updated;
                      folderTree = updated.index.tree;
                      selected = updated.index.byPath[selectedPath];
                      preview = null;
                      previewText = null;
                      previewError = null;
                    });
                    if (selected != null) await select(selected!);
                  }
                }
              }
              if (mounted) message('修改已保存回压缩包');
            } catch (e) {
              await service.retain(file);
              if (mounted) {
                message('保存失败：$e\n临时文件仍保留在 ${file.path}', error: true);
              }
            } finally {
              feedback.finish();
              if (mounted) setState(() => busy = false);
            }
          } else {
            try {
              if (action == 'discard') {
                await service.discard(file);
              } else {
                await service.retain(file);
              }
            } finally {
              if (mounted) setState(() => busy = false);
            }
          }
        });
      }
    } finally {
      prompting = false;
    }
  }

  List<ArchiveEntry> itemsInFolder(String path) {
    final doc = document;
    if (doc == null) return const [];
    if (path != folder || search.text.isEmpty) return doc.index.inFolder(path);
    if (searchedDocument == doc &&
        searchedFolder == path &&
        searchedTerm == search.text) {
      return searchResults ?? const [];
    }
    return const [];
  }

  List<ArchiveEntry> sortedListItems(String path) {
    final entries = List<ArchiveEntry>.of(itemsInFolder(path));
    entries.sort((a, b) {
      if (a.directory != b.directory) return a.directory ? -1 : 1;
      var result = switch (listSortColumn) {
        'size' => a.size.compareTo(b.size),
        'modified' => (a.modified?.millisecondsSinceEpoch ?? 0).compareTo(
          b.modified?.millisecondsSinceEpoch ?? 0,
        ),
        'kind' => kind(a).toLowerCase().compareTo(kind(b).toLowerCase()),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      if (result == 0) {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return listSortAscending ? result : -result;
    });
    return entries;
  }

  (String, String) listingKey(String path) =>
      (path, path == folder ? search.text : '');

  DirectoryListing listingInFolder(String path) => DirectoryListing(
    !grid && !columns && !gallery ? sortedListItems(path) : itemsInFolder(path),
    expanded: expandedListings.contains(listingKey(path)),
  );

  List<ArchiveEntry> get visibleItems => listingInFolder(folder);

  Widget remainingItems(String path, DirectoryListing listing) =>
      FileItemSurface(
        key: ValueKey('expand-remaining-$path'),
        name: '双击展开剩余 ${listing.remainingCount} 项',
        selected: false,
        onSelect: null,
        onActivate: busy
            ? null
            : () => setState(() {
                expandedListings.add(listingKey(path));
              }),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AppText(
              '双击展开剩余 ${listing.remainingCount} 项',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ),
      );
  Future<void> searchFolder(int request) async {
    final doc = document, path = folder, term = search.text;
    if (doc == null || term.isEmpty) return;
    List<ArchiveEntry> result;
    try {
      result = await observed(
        '正在搜索',
        () => compute(filterArchiveEntries, (
          doc.index.inFolder(path),
          term,
        ), debugLabel: 'hizip-search'),
        success: '搜索已完成',
        current: () =>
            searchRequest == request &&
            document == doc &&
            folder == path &&
            search.text == term,
        reportFastSuccess: false,
      );
    } catch (_) {
      return;
    }
    if (!mounted ||
        searchRequest != request ||
        document != doc ||
        folder != path ||
        search.text != term) {
      return;
    }
    setState(() {
      searchedDocument = doc;
      searchedFolder = path;
      searchedTerm = term;
      searchResults = result;
    });
    ensureGallerySelection();
  }

  void syncFileCommands() {
    unawaited(
      desktop.enableFileCommands(fileFocus.hasFocus && !searchFocus.hasFocus),
    );
  }

  void selectAllFiles() {
    if (busy || searchFocus.hasFocus) return;
    clearPreparedDrag();
    setState(() {
      selectedPaths
        ..clear()
        ..addAll(itemsInFolder(folder).map((e) => e.path));
      selected = visibleItems.firstOrNull;
    });
  }

  Future<List<String>> exported(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) {
    final key = '${doc.path}\u0000${entries.map((e) => e.path).join('\u0000')}';
    return transferExports.putIfAbsent(key, () async {
      try {
        return await service.exportEntries(doc, entries);
      } catch (_) {
        transferExports.remove(key);
        rethrow;
      }
    });
  }

  void warmExport() {
    if (!widget.enableNativeTransfers ||
        document == null ||
        selection.isEmpty) {
      return;
    }
    final entries = selection;
    if (entries.length != 1 ||
        !entries.single.canExtract ||
        entries.single.size > 512 * 1024) {
      return;
    }
    final doc = document!;
    warmTimer?.cancel();
    warmTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted ||
          busy ||
          document != doc ||
          selectedPaths.length != 1 ||
          !selectedPaths.contains(entries.single.path)) {
        return;
      }
      unawaited(
        exported(doc, entries).then<void>((_) {}, onError: (Object _) {}),
      );
    });
  }

  List<ArchiveEntry> get selection => selectedPaths
      .map((path) => document?.index.byPath[path])
      .whereType<ArchiveEntry>()
      .toList();

  void selectFromPointer(ArchiveEntry entry) {
    pointerSelectedItem = true;
    fileFocus.requestFocus();
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final toggle =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final extend =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    if (toggle && selectedPaths.contains(entry.path)) {
      selectedPaths.remove(entry.path);
      final remaining = selection.firstOrNull;
      if (remaining == null) {
        clearSelection();
      } else {
        unawaited(select(remaining, preserveSelection: true));
      }
      return;
    }
    if (extend && selected != null) {
      final items = visibleItems;
      final a = items.indexWhere((e) => e.path == selected!.path),
          b = items.indexWhere((e) => e.path == entry.path);
      if (a >= 0 && b >= 0) {
        selectedPaths.addAll(
          items.sublist(a < b ? a : b, (a > b ? a : b) + 1).map((e) => e.path),
        );
      }
    }
    select(entry, preserveSelection: toggle || extend);
  }

  void clearSelection() {
    pointerSelectedItem = false;
    if (selected == null && selectedPaths.isEmpty) return;
    ++previewRequest;
    ++systemPreviewRequest;
    unawaited(desktop.closeQuickLook());
    setState(() {
      selected = null;
      selectedPaths.clear();
      selectedApplication = null;
      preview = null;
      previewText = null;
      previewError = null;
      status = defaultStatus();
    });
  }

  Future<void> copyFiles() async {
    if (busy || searchFocus.hasFocus || document == null || selection.isEmpty) {
      return;
    }
    final doc = document!, entries = selection;
    await run(() async {
      final paths = await exported(doc, entries);
      await clipboard.writeFiles(paths);
      await service.retainClipboardExports(paths);
      message('已复制 ${paths.length} 个项目');
    }, title: '正在复制文件');
  }

  Future<void> pasteFiles() async {
    if (busy || searchFocus.hasFocus) return;
    try {
      final paths = await clipboard.readFiles();
      if (!mounted) return;
      if (paths.isEmpty) {
        message('剪贴板中没有文件');
        return;
      }
      await receiveFiles(paths, folder);
    } catch (e) {
      if (mounted) message(e.toString(), error: true);
    }
  }

  void refreshDocument(ArchiveDocument result) {
    if (!mounted) return;
    ++previewRequest;
    ++systemPreviewRequest;
    unawaited(desktop.closeQuickLook());
    setState(() {
      clearPreparedDrag();
      transferExports.clear();
      document = result;
      tabFor(result.path)?.document = result;
      folderTree = result.index.tree;
      selected = null;
      selectedPaths.clear();
      selectedApplication = null;
      preview = null;
      previewText = null;
      previewError = null;
      status = defaultStatus();
      status = '${result.entries.length} 个项目 · ${result.format}';
    });
  }

  Future<void> receiveFiles(List<String> paths, String destination) async {
    if (busy || paths.isEmpty) return;
    final doc = document;
    if (doc == null) {
      if (paths.every(
        (path) => readableArchiveExtensions.contains(
          p.extension(path).replaceFirst('.', '').toLowerCase(),
        ),
      )) {
        for (final path in paths) {
          await loadArchive(path);
        }
        return;
      }
      final target = await getSaveLocation(
        suggestedName: 'Archive.zip',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'ZIP', extensions: ['zip']),
        ],
      );
      if (target == null || !mounted) return;
      await run(
        () async {
          await service.create(target.path, paths);
          message('压缩包已创建');
        },
        title: '正在创建压缩包',
        archivePath: target.path,
      );
      await loadArchive(target.path, encoding: settings.archive.createEncoding);
      return;
    }
    await run(() async {
      final result = await service.importFiles(doc, paths, destination);
      refreshDocument(result);
      message('已传入 ${paths.length} 个项目');
    }, title: '正在传入文件');
  }

  Future<String?> entryNameDialog(bool directory) async {
    if (!mounted) return null;
    final input = TextEditingController(
      text: translateAppText(
        directory ? '未命名文件夹' : '未命名.txt',
        settings.locale.languageCode,
      ),
    );
    setState(() => entryNameInput = input);
    try {
      final action = await feedback.ask(
        TaskFeedback(
          title: directory ? '新建文件夹' : '新建空白文档',
          actions: const {'cancel': '取消', 'create': '创建'},
        ),
      );
      return action == 'create' ? input.text : null;
    } finally {
      if (mounted) setState(() => entryNameInput = null);
      input.dispose();
    }
  }

  Future<void> newEntry({bool directory = false, String? destination}) async {
    final doc = document;
    if (busy || closing || doc == null || !doc.writable) return;
    final target = destination ?? folder;
    await taskQueue.run(doc.path, directory ? '正在新建文件夹' : '正在新建空白文档', () async {
      if (!mounted || closing) return;
      String? name;
      setState(() => busy = true);
      try {
        name = await entryNameDialog(directory);
      } catch (e) {
        if (mounted) message(e.toString(), error: true);
      } finally {
        if (mounted) setState(() => busy = false);
      }
      if (!mounted || name == null || closing) return;
      await run(() async {
        final updated = await service.createEntry(
          doc,
          target,
          name!.trim(),
          directory: directory,
        );
        refreshDocument(updated);
        navigate(target);
        final added = updated.index
            .inFolder(target)
            .where(
              (entry) => !doc.index.byNormalized.containsKey(entry.normalized),
            )
            .firstOrNull;
        if (added != null) await select(added);
        message(directory ? '文件夹已创建' : '空白文档已创建');
      }, title: directory ? '正在新建文件夹' : '正在新建空白文档');
    });
  }

  Future<void> deleteSelection() async {
    final doc = document;
    final entries = List<ArchiveEntry>.of(selection);
    if (busy || closing || doc == null || !doc.writable || entries.isEmpty) {
      return;
    }
    await taskQueue.run(doc.path, '等待删除确认', () async {
      if (!mounted || closing) return;
      setState(() => busy = true);
      final action = await feedback.ask(
        TaskFeedback(
          title: '删除所选项目？',
          detail: '${entries.length} 个所选项目将从压缩包中删除，文件夹内的内容也会删除。',
          actions: const {'cancel': '取消', 'delete': '删除'},
        ),
      );
      if (!mounted) return;
      setState(() => busy = false);
      if (action != 'delete' || closing) return;
      await run(() async {
        final updated = await service.deleteEntries(doc, entries);
        pending.removeWhere(
          (file) =>
              file.archive == doc.path &&
              !updated.index.byPath.containsKey(file.entry),
        );
        refreshDocument(updated);
        var target = folder;
        while (target.isNotEmpty &&
            !updated.index.children.containsKey(target)) {
          target = p.posix.dirname(target);
          if (target == '.') target = '';
        }
        navigate(target);
        message('已删除 ${entries.length} 个项目');
      }, title: '正在删除文件');
    });
  }

  DropOperation dropOperation(DropOverEvent event, String destination) {
    if (busy ||
        !service.supported ||
        (document != null && !document!.writable)) {
      return DropOperation.none;
    }
    if (event.session.items.isEmpty ||
        event.session.items.any((e) => !e.canProvide(Formats.fileUri))) {
      return DropOperation.none;
    }
    final internal =
        activeDrag?.$1.path == document?.path && activeDrag != null ||
        event.session.items.any(
          (e) =>
              e.localData is Map &&
              (e.localData as Map)['archive'] == document?.path,
        );
    if (internal) {
      final paths = activeDrag != null
          ? activeDrag!.$2.map((e) => e.normalized)
          : event.session.items.expand(
              (e) => e.localData is Map
                  ? ((e.localData as Map)['entries'] as List? ?? [])
                        .cast<String>()
                  : <String>[],
            );
      if (paths.any(
        (path) => destination == path || destination.startsWith('$path/'),
      )) {
        return DropOperation.none;
      }
      if (event.session.allowedOperations.contains(DropOperation.move)) {
        return DropOperation.move;
      }
    }
    return event.session.allowedOperations.contains(DropOperation.copy)
        ? DropOperation.copy
        : DropOperation.none;
  }

  Future<void> performDrop(PerformDropEvent event, String destination) async {
    if (busy) return;
    final doc = document;
    final internal =
        doc != null &&
        (activeDrag?.$1.path == doc.path ||
            event.session.items.every(
              (e) =>
                  e.localData is Map &&
                  (e.localData as Map)['archive'] == doc.path,
            ));
    if (internal) {
      final paths = activeDrag != null
          ? activeDrag!.$2.map((e) => e.path).toSet()
          : event.session.items
                .expand(
                  (e) =>
                      ((e.localData as Map)['entries'] as List).cast<String>(),
                )
                .toSet();
      final entries = <ArchiveEntry>[];
      for (final path in paths) {
        final item = doc.index.byPath[path];
        if (item == null) {
          message('来源目录已变化，请重新拖拽', error: true);
          return;
        }
        entries.add(item);
      }
      await run(
        () async {
          final move = event.acceptedOperation == DropOperation.move;
          final result = await service.transferEntries(
            doc,
            entries,
            destination,
            move: move,
          );
          refreshDocument(result);
          message(
            move ? '已移动 ${entries.length} 个项目' : '已复制 ${entries.length} 个项目',
          );
        },
        title: event.acceptedOperation == DropOperation.move
            ? '正在移动文件'
            : '正在复制文件',
      );
    } else {
      try {
        final paths = <String>[];
        for (final item in event.session.items) {
          final reader = item.dataReader;
          if (reader == null) continue;
          final completion = Completer<Uri?>();
          final progress = reader.getValue(
            Formats.fileUri,
            completion.complete,
            onError: completion.completeError,
          );
          if (progress == null && !completion.isCompleted) {
            completion.complete(null);
          }
          final uri = await completion.future;
          if (uri != null && uri.scheme == 'file') paths.add(uri.toFilePath());
        }
        if (paths.isEmpty) throw StateError('无法读取拖入的文件。');
        await receiveFiles(paths, destination);
      } catch (e) {
        if (mounted) message(e.toString(), error: true);
      }
    }
  }

  Widget dropTarget(String destination, Widget child) {
    final touchTarget = TouchFileDropTarget(
      controller: touchDrops,
      accepts: () => acceptsTouchDrop(destination),
      onDrop: () => unawaited(performTouchDrop(destination)),
      child: child,
    );
    return !widget.enableNativeTransfers
        ? touchTarget
        : FileDropTarget(
            operation: (event) => dropOperation(event, destination),
            perform: (event) => performDrop(event, destination),
            child: touchTarget,
          );
  }

  bool acceptsTouchDrop(String destination) {
    final drag = touchDrag;
    if (drag == null ||
        busy ||
        closing ||
        document != drag.$1 ||
        !drag.$1.writable) {
      return false;
    }
    return drag.$2.every(
      (entry) =>
          destination != entry.normalized &&
          !destination.startsWith('${entry.normalized}/') &&
          p.posix.dirname(entry.normalized).replaceFirst(RegExp(r'^\.$'), '') !=
              destination,
    );
  }

  Future<void> performTouchDrop(String destination) async {
    if (!acceptsTouchDrop(destination)) return;
    final (doc, entries) = touchDrag!;
    touchDrag = null;
    await run(() async {
      final updated = await service.transferEntries(
        doc,
        entries,
        destination,
        move: true,
      );
      refreshDocument(updated);
      message('已移动 ${entries.length} 个项目');
    }, title: '正在移动文件');
  }

  Future<void> prepareMacDrag(ArchiveEntry entry, Rect frame) async {
    if (busy || !entry.safe || (!entry.directory && !entry.canExtract)) return;
    final doc = document!;
    final entries = selectedPaths.contains(entry.path) ? selection : [entry];
    final roots = topLevelEntries(entries);
    final bytes = roots.fold<int>(
      0,
      (sum, e) => sum + (doc.index.sizes[e.normalized] ?? e.size),
    );
    final key = '${doc.path}\u0000${roots.map((e) => e.path).join('\u0000')}';
    if (bytes > 512 * 1024 && !transferExports.containsKey(key)) return;
    final token = ++dragPreparationRequest;
    try {
      final paths = await observed(
        '正在准备拖拽文件',
        () => exported(doc, roots),
        success: '拖拽文件已准备好',
        current: () => document == doc && token == dragPreparationRequest,
        reportFastSuccess: false,
      );
      if (!mounted ||
          busy ||
          document != doc ||
          token != dragPreparationRequest) {
        return;
      }
      armedDrag = (doc, roots);
      await desktop.prepareFileDrag(
        paths,
        movable: doc.writable,
        frame: [frame.left, frame.top, frame.width, frame.height],
      );
    } catch (_) {
      /* A failed export is reported if the user starts a drag. */
    }
  }

  void clearPreparedDrag() {
    warmTimer?.cancel();
    ++dragPreparationRequest;
    armedDrag = null;
    if (widget.enableNativeTransfers && desktop.supportsQuickLook) {
      unawaited(
        desktop.prepareFileDrag([], movable: false, frame: [0, 0, 0, 0]),
      );
    }
  }

  void startTouchDrag(ArchiveEntry entry) {
    if (busy || !entry.safe) return;
    if (!entry.directory && !entry.canExtract) return;
    final doc = document;
    if (doc == null) return;
    final roots = topLevelEntries(
      selectedPaths.contains(entry.path) ? selection : [entry],
    );
    touchDrag = (doc, roots);
    feedback.action('dismiss');
    setState(() => status = '拖拽 ${roots.length} 个项目');
  }

  Future<void> startMacDrag(ArchiveEntry entry) async {
    if (busy || !entry.safe || (!entry.directory && !entry.canExtract)) return;
    final doc = document!;
    final entries = selectedPaths.contains(entry.path) ? selection : [entry];
    final roots = topLevelEntries(entries);
    try {
      setState(() => status = '正在准备拖拽文件');
      await observed(
        '正在准备拖拽文件',
        () async {
          final paths = await exported(doc, roots);
          if (!mounted || document != doc || busy) return;
          armedDrag = (doc, roots);
          activeDrag = (doc, roots);
          await desktop.startFileDrag(paths, movable: doc.writable);
          if (mounted) setState(() => status = '拖拽 ${roots.length} 个项目');
        },
        success: '拖拽文件已准备好',
        current: () => document == doc,
      );
    } catch (e) {
      activeDrag = null;
      if (mounted && document == doc && !busy) {
        message(
          e is PlatformException && e.code == 'drag_cancelled'
              ? e.message!
              : e.toString(),
          error: !(e is PlatformException && e.code == 'drag_cancelled'),
        );
      }
    }
  }

  Widget transferable(ArchiveEntry entry, Widget child) {
    if (!widget.enableNativeTransfers) {
      return entry.directory ? dropTarget(entry.normalized, child) : child;
    }
    if (desktop.supportsQuickLook) {
      return entry.directory ? dropTarget(entry.normalized, child) : child;
    }
    final content = DragItemWidget(
      dragBuilder: (context, child) => SizedBox(
        width: 180,
        height: 36,
        child: Row(
          children: [
            fileIcon(entry),
            const SizedBox(width: 8),
            Expanded(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      allowedOperations: () => [
        DropOperation.copy,
        if (document!.writable) DropOperation.move,
      ],
      dragItemProvider: (request) async {
        if (busy || !entry.safe || (!entry.directory && !entry.canExtract)) {
          return null;
        }
        setState(() => status = '正在准备拖拽文件');
        final doc = document!;
        final entries = selectedPaths.contains(entry.path)
            ? selection
            : [entry];
        final roots = topLevelEntries(entries);
        try {
          final paths = await observed(
            '正在准备拖拽文件',
            () => exported(doc, roots),
            success: '拖拽文件已准备好',
            current: () => document == doc,
          );
          final item = DragItem(
            suggestedName: entry.name,
            localData: {
              'archive': doc.path,
              'entries': roots.map((e) => e.path).toList(),
              'exports': paths,
            },
          );
          item.add(Formats.fileUri(Uri.file(paths.first)));
          if (mounted) setState(() => status = '拖拽 ${roots.length} 个项目');
          return item;
        } catch (e) {
          if (mounted && document == doc && !busy) {
            message(e.toString(), error: true);
          }
          return null;
        }
      },
      child: DraggableWidget(
        onDragConfiguration: (configuration, session) {
          final first = configuration.items.first;
          final paths = ((first.item.localData as Map)['exports'] as List)
              .cast<String>();
          void draggingChanged() {
            if (session.dragging.value && mounted) feedback.action('dismiss');
          }

          void completed() {
            final result = session.dragCompleted.value;
            if (result == null) return;
            session.dragCompleted.removeListener(completed);
            session.dragging.removeListener(draggingChanged);
            if (mounted && !busy && !closing) {
              message(
                result == DropOperation.none ||
                        result == DropOperation.userCancelled
                    ? '拖拽已取消'
                    : result == DropOperation.forbidden
                    ? '目标不接受此拖拽'
                    : '拖拽完成：${paths.length} 个项目',
                error: result == DropOperation.forbidden,
              );
            }
          }

          session.dragging.addListener(draggingChanged);
          session.dragCompleted.addListener(completed);
          for (final path in paths.skip(1)) {
            final item = DragItem(
              suggestedName: p.basename(path),
              localData: {'archive': document!.path, 'entries': <String>[]},
            );
            item.add(Formats.fileUri(Uri.file(path)));
            configuration.items.add(
              DragConfigurationItem(item: item, image: first.image),
            );
          }
          return configuration;
        },
        child: child,
      ),
    );
    return entry.directory ? dropTarget(entry.normalized, content) : content;
  }

  KeyEventResult handleFileKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus ||
        searchFocus.hasFocus ||
        busy ||
        document == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        copyFiles();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        pasteFiles();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyA) {
        selectAllFiles();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        deleteSelection();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyN && keys.isShiftPressed) {
        newEntry(directory: true);
        return KeyEventResult.handled;
      }
    }
    if (desktop.supportsQuickLook &&
        event.logicalKey == LogicalKeyboardKey.space &&
        !keys.isMetaPressed &&
        !keys.isControlPressed &&
        !keys.isAltPressed) {
      quickLook();
      return KeyEventResult.handled;
    }
    if ((gallery || grid) &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      moveSelection(event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      moveSelection(grid ? gridColumns : 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      moveSelection(grid ? -gridColumns : -1);
      return KeyEventResult.handled;
    }
    if (columns &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        selected?.directory == true) {
      navigate(selected!.normalized);
      moveSelection(1);
      revealColumns();
      return KeyEventResult.handled;
    }
    if (columns &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        folder.isNotEmpty) {
      final previous = folder;
      navigate(p.posix.dirname(folder) == '.' ? '' : p.posix.dirname(folder));
      final parentEntry = visibleItems
          .where((e) => e.normalized == previous)
          .firstOrNull;
      if (parentEntry != null) select(parentEntry);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && selected != null) {
      openEntry(selected!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void moveSelection(int delta, {bool fromQuickLook = false}) {
    if (busy || document == null) return;
    final items = fromQuickLook
        ? visibleItems.where((e) => e.canExtract).toList()
        : visibleItems;
    if (items.isEmpty) return;
    final index = items.indexWhere((e) => e.path == selected?.path);
    if (grid &&
        !fromQuickLook &&
        index >= 0 &&
        (index + delta < 0 || index + delta >= items.length)) {
      return;
    }
    final next = index < 0
        ? (delta > 0 ? 0 : items.length - 1)
        : (index + delta).clamp(0, items.length - 1);
    unawaited(select(items[next]));
    if (columns) revealColumns();
    final activeScroll = columns ? columnLists[folder] : listScroll;
    if (grid && activeScroll != null && activeScroll.hasClients) {
      final rowIndex =
          visibleItems.indexWhere((e) => e.path == items[next].path) ~/
          gridColumns;
      final top = gridPadding + rowIndex * (gridTileExtent + gridSpacing);
      final bottom = top + gridTileExtent;
      var offset = activeScroll.offset;
      if (top < offset) offset = top;
      if (bottom > offset + activeScroll.position.viewportDimension) {
        offset = bottom - activeScroll.position.viewportDimension;
      }
      activeScroll.jumpTo(
        offset.clamp(0, activeScroll.position.maxScrollExtent),
      );
    }
    if (activeScroll != null && activeScroll.hasClients && !grid && !gallery) {
      final rowIndex = visibleItems.indexWhere(
        (e) => e.path == items[next].path,
      );
      final extent = rowExtent(iconSize);
      final top = listInset + rowIndex * extent, bottom = top + extent;
      var offset = activeScroll.offset;
      if (top < offset) offset = top;
      if (bottom > offset + activeScroll.position.viewportDimension) {
        offset = bottom - activeScroll.position.viewportDimension;
      }
      activeScroll.jumpTo(
        offset.clamp(0, activeScroll.position.maxScrollExtent),
      );
    }
  }

  void expandAncestors(String path) {
    ++sidebarRevision;
    expandedFolders.add('');
    final parts = path.split('/');
    for (var i = 1; path.isNotEmpty && i <= parts.length; i++) {
      expandedFolders.add(parts.take(i).join('/'));
    }
  }

  Future<void> updateApplication(ArchiveEntry entry, int token) async {
    final app = entry.directory
        ? null
        : await desktop.defaultApplication(entry.name);
    if (mounted && token == previewRequest) {
      setState(() => selectedApplication = app);
    }
  }

  Future<void> updateSystemPreview(ArchiveEntry entry, int token) async {
    if (!desktop.supportsQuickLook) return;
    try {
      if (!await desktop.quickLookVisible()) return;
      if (entry.directory) {
        ++systemPreviewRequest;
        await desktop.closeQuickLook();
        return;
      }
      await showSystemPreview(entry, token);
    } catch (e) {
      if (mounted && token == previewRequest) message('系统预览失败：$e', error: true);
    }
  }

  Future<void> showSystemPreview(ArchiveEntry entry, int selectionToken) async {
    if (closing || selectionToken != previewRequest || document == null) return;
    final request = ++systemPreviewRequest;
    openingSystemPreview = true;
    try {
      final file = await observed(
        '正在打开文件',
        () => service.prepareExternal(document!, entry),
        success: '文件已准备好：${entry.name}',
        current: () =>
            selectionToken == previewRequest && request == systemPreviewRequest,
      );
      if (!mounted ||
          selectionToken != previewRequest ||
          request != systemPreviewRequest) {
        return;
      }
      await desktop.showQuickLook(file.path);
    } finally {
      if (request == systemPreviewRequest) openingSystemPreview = false;
    }
  }

  Future<void> quickLook() async {
    if (searchFocus.hasFocus ||
        selected == null ||
        selected!.directory ||
        busy ||
        !desktop.supportsQuickLook) {
      return;
    }
    try {
      if (openingSystemPreview || await desktop.quickLookVisible()) {
        ++systemPreviewRequest;
        openingSystemPreview = false;
        await desktop.closeQuickLook();
      } else {
        await showSystemPreview(selected!, previewRequest);
      }
    } catch (e) {
      if (mounted) message('系统预览失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppLanguageScope(
    languageCode: settings.locale.languageCode,
    child: workspaceBody(context),
  );

  Widget workspaceBody(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): openSettings,
      const SingleActivator(LogicalKeyboardKey.comma, control: true):
          openSettings,
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () {
        if (!busy) pickArchive();
      },
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
        if (!busy) pickArchive();
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): goBack,
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
          closeTab(document?.path),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
          closeTab(document?.path),
    },
    child: Focus(
      focusNode: fileFocus,
      autofocus: true,
      onKeyEvent: handleFileKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          unawaited(
            desktop.updateMenuState(
              busy: busy,
              hasDocument: document != null,
              encoding: document?.encoding ?? settings.archive.readEncoding,
              writable: document?.writable ?? false,
              hasSelection: selection.isNotEmpty,
            ),
          );
          final desktopLayout = constraints.maxWidth >= 800;
          inspectorVisible = document != null && inspector && desktopLayout;
          final leftWidth = sidebarWidth.clamp(
            160.0,
            (constraints.maxWidth * .28).clamp(160.0, double.infinity),
          );
          final rightWidth = inspectorWidth.clamp(
            220.0,
            (constraints.maxWidth * .32).clamp(220.0, double.infinity),
          );
          return ListenableBuilder(
            listenable: feedback,
            builder: (_, _) => Stack(
              children: [
                Scaffold(
                  body: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification) {
                        clearPreparedDrag();
                      }
                      return false;
                    },
                    child: SafeArea(
                      child: Column(
                        children: [
                          toolbar(desktopLayout),
                          Expanded(
                            child: Scaffold(
                              key: contentScaffold,
                              drawer: desktopLayout
                                  ? null
                                  : Drawer(width: 240, child: sidebar()),
                              body: Row(
                                children: [
                                  if (desktopLayout)
                                    SizedBox(
                                      width: leftWidth,
                                      child: sidebar(),
                                    ),
                                  if (desktopLayout)
                                    splitter(
                                      'sidebar-resizer',
                                      (dx) =>
                                          sidebarWidth = (leftWidth + dx).clamp(
                                            160.0,
                                            (constraints.maxWidth * .28).clamp(
                                              160.0,
                                              double.infinity,
                                            ),
                                          ),
                                    ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        if (tabs.length > 1) archiveTabs(),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: directoryBackground(
                                                  child: document == null
                                                      ? dropTarget(
                                                          '',
                                                          emptyWorkspace(),
                                                        )
                                                      : FileContextMenu(
                                                          onNewFolder:
                                                              busy ||
                                                                  !document!
                                                                      .writable
                                                              ? null
                                                              : () => newEntry(
                                                                  directory:
                                                                      true,
                                                                ),
                                                          onNewDocument:
                                                              busy ||
                                                                  !document!
                                                                      .writable
                                                              ? null
                                                              : () =>
                                                                    newEntry(),
                                                          onPaste:
                                                              busy ||
                                                                  !document!
                                                                      .writable
                                                              ? null
                                                              : pasteFiles,
                                                          child: dropTarget(
                                                            folder,
                                                            browser(),
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              if (inspectorVisible) ...[
                                                splitter(
                                                  'inspector-resizer',
                                                  (dx) => inspectorWidth =
                                                      (rightWidth - dx).clamp(
                                                        220.0,
                                                        (constraints.maxWidth *
                                                                .32)
                                                            .clamp(
                                                              220.0,
                                                              double.infinity,
                                                            ),
                                                      ),
                                                ),
                                                SizedBox(
                                                  width: rightWidth,
                                                  child: inspectorPanel(),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          footer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget splitter(String key, void Function(double) resize) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (event) {
        clearPreparedDrag();
        setState(() => resize(event.delta.dx));
        saveBrowsingPreferences();
      },
      child: Container(
        width: 1,
        color: desktopColor(context, 0xffd8d8d8, 0xff414248),
      ),
    ),
  );

  void revealColumns() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && columns && columnScroll.hasClients) {
        columnScroll.jumpTo(columnScroll.position.maxScrollExtent);
      }
    });
  }

  List<String> get columnPaths {
    final paths = <String>[''];
    if (folder.isNotEmpty) {
      final parts = folder.split('/');
      for (var i = 1; i <= parts.length; i++) {
        paths.add(parts.take(i).join('/'));
      }
    }
    final entry = selected;
    if (entry != null &&
        entry.directory &&
        !paths.contains(entry.normalized) &&
        document!.index.byPath[entry.path]?.path == entry.path &&
        (p.posix.dirname(entry.normalized) == '.'
                ? ''
                : p.posix.dirname(entry.normalized)) ==
            folder) {
      paths.add(entry.normalized);
    }
    return paths;
  }

  Widget columnBrowser() {
    final paths = columnPaths;
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: columnScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: columnScroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final parent in paths)
                SizedBox(
                  width: 220,
                  child: Container(
                    key: ValueKey('column-$parent'),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: desktopColor(context, 0xffdedede, 0xff414248),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 27,
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                listInset + (iconSize * .25).clamp(3.0, 10.0),
                          ),
                          color: desktopColor(context, 0xfff7f7f7, 0xff292a2e),
                          child: AppText(
                            parent.isEmpty
                                ? p.basename(document!.path)
                                : p.posix.basename(parent),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                        Expanded(
                          child: FileContextMenu(
                            onPaste: busy || !document!.writable
                                ? null
                                : () => pasteInto(parent),
                            child: dropTarget(parent, columnList(parent)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget columnList(String parent) {
    final items = listingInFolder(parent);
    if (items.isEmpty) {
      return Center(
        child: AppText(
          search.text.isNotEmpty && parent == folder ? '没有匹配的文件' : '空文件夹',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
      );
    }
    final rowIconSize = iconSize;
    final rowHeight = rowExtent(rowIconSize);
    final rowPadding = (rowIconSize * .25).clamp(3.0, 10.0);
    final controller = columnLists.putIfAbsent(
      parent,
      () => ScrollController(),
    );
    return ListView.builder(
      controller: controller,
      scrollCacheExtent: ScrollCacheExtent.pixels(0),
      addAutomaticKeepAlives: false,
      padding: const EdgeInsets.all(listInset),
      itemExtent: rowHeight,
      itemCount: items.length + (items.remainingCount > 0 ? 1 : 0),
      itemBuilder: (_, i) => i == items.length
          ? remainingItems(parent, items)
          : row(
              items[i],
              true,
              columnParent: parent,
              joinPrevious: i > 0 && selectedPaths.contains(items[i - 1].path),
              joinNext:
                  i + 1 < items.length &&
                  selectedPaths.contains(items[i + 1].path),
              iconSize: rowIconSize,
              horizontalPadding: rowPadding,
              height: rowHeight,
            ),
    );
  }

  Future<void> chooseOpenApplication(ArchiveEntry entry) async {
    try {
      final app = await desktop.chooseApplication(entry.name);
      if (app != null && mounted) await openEntry(entry, application: app);
    } catch (e) {
      if (mounted) message(e.toString(), error: true);
    }
  }

  Widget applicationPicker(ArchiveEntry entry) => FileContextMenu(
    applicationOnly: true,
    enabled: !busy,
    primaryClick: true,
    openUpwards: true,
    childBuilder: (_, shown, _) => Semantics(
      button: true,
      expanded: shown,
      child: AppTooltip(
        message: '打开方式',
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            shown ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_up,
            size: 12,
            color: muted,
          ),
        ),
      ),
    ),
    applications: () => desktop.applicationsForFile(entry.name),
    onOpenWith: busy ? null : (app) => openEntry(entry, application: app),
    onChooseApplication: busy ? null : () => chooseOpenApplication(entry),
    child: const AppTooltip(
      message: '打开方式',
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(CupertinoIcons.chevron_up, size: 12, color: muted),
      ),
    ),
  );

  Widget contextMenu(
    ArchiveEntry entry,
    Widget child, {
    String? columnParent,
  }) => FileContextMenu(
    onSelect: busy
        ? null
        : () {
            if (columnParent != null) navigate(columnParent);
            fileFocus.requestFocus();
            select(
              entry,
              preserveSelection: selectedPaths.contains(entry.path),
            );
          },
    onOpen: busy || (!entry.directory && !entry.canExtract)
        ? null
        : () => openEntry(entry),
    onPreview: desktop.supportsQuickLook && !busy && entry.canExtract
        ? quickLook
        : null,
    onCopy: busy || !entry.safe ? null : copyFiles,
    onPaste: busy || !document!.writable
        ? null
        : () => pasteInto(entry.directory ? entry.normalized : folder),
    onExtract: busy || !entry.safe ? null : () => extract(onlySelected: true),
    onDelete: busy || !document!.writable ? null : deleteSelection,
    onNewFolder: busy || !document!.writable
        ? null
        : () => newEntry(
            directory: true,
            destination: entry.directory ? entry.normalized : folder,
          ),
    onNewDocument: busy || !document!.writable
        ? null
        : () => newEntry(
            destination: entry.directory ? entry.normalized : folder,
          ),
    applications: desktop.supportsFileIntegration && entry.canExtract
        ? () => desktop.applicationsForFile(entry.name)
        : null,
    onOpenWith: busy || !desktop.supportsFileIntegration || !entry.canExtract
        ? null
        : (app) => openEntry(entry, application: app),
    onChooseApplication: busy || !desktop.supportsFileIntegration
        ? null
        : () => chooseOpenApplication(entry),
    onTouchDragStart:
        !busy &&
            !closing &&
            document!.writable &&
            entry.safe &&
            (entry.directory || entry.canExtract)
        ? () => startTouchDrag(entry)
        : null,
    onTouchDragUpdate: touchDrops.update,
    onTouchDragEnd: (position) {
      touchDrops.drop(position);
      touchDrag = null;
    },
    onTouchDragCancel: () {
      touchDrag = null;
      touchDrops.cancel();
    },
    touchDragLabel: entry.name,
    child: Listener(
      onPointerDown: (_) => pointerSelectedItem = true,
      child: child,
    ),
  );

  Future<void> pasteInto(String destination) async {
    if (busy) return;
    try {
      final paths = await clipboard.readFiles();
      if (!mounted) return;
      if (paths.isEmpty) {
        message('剪贴板中没有文件');
        return;
      }
      await receiveFiles(paths, destination);
    } catch (e) {
      if (mounted) message(e.toString(), error: true);
    }
  }

  Widget treeContext(ArchiveFolder node, Widget child) {
    if (node.path.isEmpty) {
      return FileContextMenu(
        onOpen: busy ? null : () => navigate(''),
        onPaste: busy || !document!.writable ? null : () => pasteInto(''),
        onNewFolder: busy || !document!.writable
            ? null
            : () => newEntry(directory: true, destination: ''),
        onNewDocument: busy || !document!.writable
            ? null
            : () => newEntry(destination: ''),
        child: child,
      );
    }
    final parent = p.posix.dirname(node.path) == '.'
        ? ''
        : p.posix.dirname(node.path);
    final entry = document!.index.byNormalized[node.path]!;
    return dropTarget(
      node.path,
      contextMenu(entry, child, columnParent: parent),
    );
  }

  Widget sidebar() {
    final sources = [
      for (final tab in tabs)
        (
          tab,
          tab.document.index.tree,
          tab.document.path == document?.path ? sidebarRevision : tab.revision,
        ),
    ];
    if (!listEquals(sidebarSources, sources)) {
      sidebarSources = sources;
      sidebarRows = buildSidebarRows();
    }
    final rows = sidebarRows;
    return sidebarContent(rows);
  }

  List<(_ArchiveTab, ArchiveFolder, int)> buildSidebarRows() {
    final rows = <(_ArchiveTab, ArchiveFolder, int)>[];
    for (final tab in tabs) {
      final active = tab.document.path == document?.path;
      final tree = tab.document.index.tree;
      final expanded = active ? expandedFolders : tab.expanded;
      final revision = active ? sidebarRevision : tab.revision;
      if (tab.cachedTree != tree || tab.cachedRevision != revision) {
        final cached = <(ArchiveFolder, int)>[];
        void visit(ArchiveFolder node, int depth) {
          cached.add((node, depth));
          if (expanded.contains(node.path)) {
            for (final child in node.children) {
              visit(child, depth + 1);
            }
          }
        }

        visit(tree, 0);
        tab.rows = cached;
        tab.cachedTree = tree;
        tab.cachedRevision = revision;
      }
      rows.addAll(tab.rows.map((row) => (tab, row.$1, row.$2)));
    }
    return rows;
  }

  Widget sidebarContent(List<(_ArchiveTab, ArchiveFolder, int)> rows) {
    return Container(
      decoration: BoxDecoration(
        color: desktopColor(context, 0xfff3f3f3, 0xff27282b),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: AppText('目录', style: TextStyle(fontSize: 11, color: muted)),
          ),
          Expanded(
            child: document == null
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: AppText(
                      '未打开压缩包',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    scrollCacheExtent: ScrollCacheExtent.pixels(0),
                    addAutomaticKeepAlives: false,
                    controller: sidebarScroll,
                    padding: const EdgeInsets.all(listInset),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final (tab, node, depth) = rows[index];
                      final active = tab.document.path == document?.path;
                      final root = node.path.isEmpty;
                      final label = root
                          ? p.basename(tab.document.path)
                          : node.name;
                      final expanded = active ? expandedFolders : tab.expanded;
                      Widget tabContext(ArchiveFolder node, Widget child) =>
                          active ? treeContext(node, child) : child;
                      Widget tabDrop(String path, Widget child) =>
                          active ? dropTarget(path, child) : child;
                      return KeyedSubtree(
                        key: root
                            ? ValueKey('archive-root-${tab.document.path}')
                            : null,
                        child: tabContext(
                          node,
                          tabDrop(
                            node.path,
                            Semantics(
                              selected: active && folder == node.path,
                              child: Container(
                                key: ValueKey(
                                  active
                                      ? 'tree-${node.path}'
                                      : 'tree-${tab.document.path}-${node.path}',
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: active && folder == node.path
                                      ? desktopColor(
                                          context,
                                          0xffdedede,
                                          0xff464646,
                                        )
                                      : Colors.transparent,
                                ),
                                height: 29,
                                padding: EdgeInsets.only(
                                  left: (depth * 14.0).clamp(
                                    0,
                                    (sidebarWidth - 100).clamp(0, 140),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 23,
                                      child: node.children.isEmpty
                                          ? const SizedBox()
                                          : GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => setState(() {
                                                if (active) {
                                                  ++sidebarRevision;
                                                } else {
                                                  ++tab.revision;
                                                }
                                                if (!expanded.add(node.path)) {
                                                  expanded.remove(node.path);
                                                }
                                              }),
                                              child: Icon(
                                                expanded.contains(node.path)
                                                    ? CupertinoIcons
                                                          .chevron_down
                                                    : CupertinoIcons
                                                          .chevron_right,
                                                size: 10,
                                                color: desktopColor(
                                                  context,
                                                  0xff646464,
                                                  0xffbbbbc2,
                                                ),
                                              ),
                                            ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: busy
                                            ? null
                                            : () {
                                                if (!active) activateTab(tab);
                                                navigate(node.path);
                                                focusSidebar();
                                                fileFocus.requestFocus();
                                                if (contentScaffold
                                                        .currentState
                                                        ?.isDrawerOpen ==
                                                    true) {
                                                  contentScaffold.currentState
                                                      ?.closeDrawer();
                                                }
                                              },
                                        child: Row(
                                          children: [
                                            fileIcon(
                                              ArchiveEntry(
                                                path: root
                                                    ? 'archive.zip'
                                                    : node.path,
                                                size: 0,
                                                directory: !root,
                                              ),
                                              size: 17,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                label,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget archiveTabs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !tabScroll.hasClients) return;
      final index = tabs.indexWhere(
        (tab) => tab.document.path == document?.path,
      );
      final start = index * 180.0;
      final position = tabScroll.position;
      if (start < position.pixels ||
          start + 180 > position.pixels + position.viewportDimension) {
        tabScroll.jumpTo(start.clamp(0, position.maxScrollExtent));
      }
    });
    return Container(
      key: const ValueKey('archive-tabs'),
      height: 36,
      decoration: BoxDecoration(
        color: desktopColor(context, 0xffe8e8eb, 0xff242529),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        controller: tabScroll,
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in tabs)
            Semantics(
              selected: tab.document.path == document?.path,
              child: Container(
                key: ValueKey('archive-tab-${tab.document.path}'),
                width: 180,
                margin: const EdgeInsets.fromLTRB(3, 4, 0, 0),
                decoration: BoxDecoration(
                  color: tab.document.path == document?.path
                      ? desktopColor(context, 0xffffffff, 0xff35363b)
                      : null,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: busy ? null : () => switchTab(tab),
                        child: Tooltip(
                          message: tab.document.path,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                fileIcon(
                                  ArchiveEntry(
                                    path: tab.document.path,
                                    size: 0,
                                    directory: false,
                                  ),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    p.basename(tab.document.path),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tab.document.path == document?.path
                                          ? ink
                                          : muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    DesktopIconButton(
                      tooltip: '关闭标签页',
                      onPressed: () => closeTab(tab.document.path),
                      icon: const Icon(CupertinoIcons.xmark, size: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget applicationMenu() {
    final available = !busy && !closing;
    final hasDocument = available && document != null;
    final writable = hasDocument && document!.writable;
    DesktopMenuAction action(
      String title,
      String command,
      bool enabled, {
      bool checked = false,
    }) => DesktopMenuAction(
      title,
      enabled ? () => handleMenuCommand(command) : null,
      checked: checked,
    );
    DesktopMenuAction submenu(String title, List<DesktopMenuAction> children) =>
        DesktopMenuAction(title, null, children: children);
    return FileContextMenu(
      key: const ValueKey('application-menu'),
      primaryClick: true,
      triggerBuilder: (_, shown, toggle) => Semantics(
        expanded: shown,
        child: DesktopIconButton(
          tooltip: '应用菜单',
          icon: const Icon(Icons.more_horiz, size: 19),
          active: shown,
          onPressed: toggle,
        ),
      ),
      actions: [
        submenu('文件', [
          action('打开…', 'open', available),
          submenu('最近打开', [
            if (recent.isEmpty) const DesktopMenuAction('暂无最近打开的文件', null),
            for (final path in recent.take(10))
              DesktopMenuAction(
                p.basename(path),
                available ? () => loadArchive(path) : null,
              ),
            DesktopMenuAction('清除菜单', () => setState(recent.clear)),
          ]),
          action('创建 ZIP…', 'create', available),
          submenu('创建压缩包', [
            for (final format in writableArchiveFormats.entries)
              action(format.value, 'create:${format.key}', available),
          ]),
          action('解压…', 'extract', hasDocument),
          action('新建文件夹…', 'newFolder', writable),
          action('新建空白文档…', 'newDocument', writable),
          action('删除…', 'delete', writable && selectedPaths.isNotEmpty),
          submenu('编码', [
            for (final encoding in archiveEncodings.entries)
              action(
                encoding.value,
                'encoding:${encoding.key}',
                hasDocument,
                checked: document?.encoding == encoding.key,
              ),
          ]),
          action('关闭标签页', 'closeArchive', hasDocument),
        ]),
        submenu('编辑', [
          action('复制', 'copy', hasDocument && selectedPaths.isNotEmpty),
          action('粘贴', 'paste', writable),
          action('全选', 'selectAll', hasDocument),
        ]),
        submenu('显示', [
          action(
            '列表视图',
            'list',
            hasDocument,
            checked: !grid && !columns && !gallery,
          ),
          action('图标视图', 'grid', hasDocument, checked: grid),
          action('多栏视图', 'columns', hasDocument, checked: columns),
          action('画廊视图', 'gallery', hasDocument, checked: gallery),
          action('预览栏', 'inspector', hasDocument, checked: inspector),
        ]),
        action('设置…', 'settings', true),
      ],
      child: const SizedBox(width: 30, height: 28),
    );
  }

  Widget toolbar(bool desktopLayout) => LayoutBuilder(
    builder: (context, constraints) {
      final searchWidth = (constraints.maxWidth * .18).clamp(110.0, 180.0);
      return Container(
        key: const ValueKey('workspace-top-bar'),
        height: windowChromeHeight(),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: desktopColor(context, 0xfff6f6f6, 0xff292a2e),
          border: Border(
            bottom: BorderSide(
              color: desktopColor(context, 0xffdadada, 0xff414248),
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: windowDragArea(const SizedBox.expand())),
            if (!desktopLayout && compactSearchOpen && document != null)
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      closeCompactSearch,
                },
                child: Row(
                  children: [
                    Expanded(child: searchField()),
                    const SizedBox(width: 8),
                    tool('关闭搜索', CupertinoIcons.xmark, closeCompactSearch),
                  ],
                ),
              )
            else
              Row(
                children: [
                  windowLeadingControls(),
                  if (!desktopLayout)
                    Builder(
                      builder: (context) => tool('目录', Icons.menu, () {
                        final scaffold = contentScaffold.currentState;
                        if (scaffold?.isDrawerOpen == true) {
                          scaffold?.closeDrawer();
                        } else {
                          scaffold?.openDrawer();
                        }
                      }),
                    ),
                  tool(
                    '返回',
                    CupertinoIcons.chevron_left,
                    busy || history.isEmpty ? null : goBack,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: document == null
                        ? windowDragArea(
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'HiZip',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : pathNavigation(),
                  ),
                  if (desktopLayout && document != null) ...[
                    tool(
                      '列表视图',
                      CupertinoIcons.list_bullet,
                      () => changeView('list'),
                      active: !grid && !columns && !gallery,
                    ),
                    tool(
                      '图标视图',
                      CupertinoIcons.square_grid_2x2,
                      () => changeView('grid'),
                      active: grid,
                    ),
                    tool(
                      '多栏视图',
                      CupertinoIcons.rectangle_split_3x1,
                      () => changeView('columns'),
                      active: columns,
                    ),
                    tool(
                      '画廊视图',
                      CupertinoIcons.rectangle_stack,
                      () => changeView('gallery'),
                      active: gallery,
                    ),
                    tool(
                      '预览栏',
                      CupertinoIcons.sidebar_right,
                      toggleInspector,
                      active: inspector,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (document != null)
                    tool(
                      '解压',
                      CupertinoIcons.arrow_down_to_line,
                      closing ? null : () => extract(),
                    ),
                  if (document != null) ...[
                    const SizedBox(width: 8),
                    if (desktopLayout)
                      SizedBox(
                        key: const ValueKey('top-search-slot'),
                        width: searchWidth,
                        child: searchField(),
                      )
                    else
                      tool('搜索', FIcons.search, () {
                        setState(() => compactSearchOpen = true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && compactSearchOpen) {
                            searchFocus.requestFocus();
                          }
                        });
                      }, active: search.text.isNotEmpty),
                    const SizedBox(width: 8),
                  ],
                  if (!desktop.supportsMenuBar) applicationMenu(),
                  windowTrailingControls(),
                ],
              ),
          ],
        ),
      );
    },
  );

  Widget tool(
    String title,
    IconData icon,
    VoidCallback? action, {
    bool active = false,
  }) => DesktopIconButton(
    tooltip: title,
    onPressed: action,
    active: active,
    icon: Icon(icon, size: 17),
  );

  void closeCompactSearch() {
    setState(() => compactSearchOpen = false);
    fileFocus.requestFocus();
  }

  Widget directoryBackground({required Widget child}) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 24,
          right: 24,
          bottom: 20,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Align(
                alignment: Alignment.bottomRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'HiZip',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: (constraints.maxWidth * .25).clamp(48.0, 144.0),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -4,
                      height: 1,
                      color: desktopColor(context, 0x0c000000, 0x14ffffff),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );

  Widget emptyWorkspace() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppText('未打开压缩包', style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 14),
        DesktopButton(
          onPressed: busy ? null : pickArchive,
          child: const AppText('打开压缩包'),
        ),
        if (!service.supported)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: AppText(
              '当前平台暂不支持压缩文件操作',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget pathNavigation() => Align(
    alignment: Alignment.centerLeft,
    child: Listener(
      key: const ValueKey('path-navigation'),
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent || !pathScroll.hasClients) return;
        final delta = event.scrollDelta.dx != 0
            ? event.scrollDelta.dx
            : event.scrollDelta.dy;
        if (delta == 0) return;
        pathScroll.jumpTo(
          (pathScroll.offset + delta).clamp(
            0.0,
            pathScroll.position.maxScrollExtent,
          ),
        );
      },
      child: IntrinsicWidth(
        child: SingleChildScrollView(
          controller: pathScroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              crumb(p.basename(document!.path), () => navigate('')),
              for (
                var i = 0;
                i < (folder.isEmpty ? 0 : folder.split('/').length);
                i++
              ) ...[
                const Icon(CupertinoIcons.chevron_right, size: 9, color: muted),
                crumb(
                  folder.split('/')[i],
                  () => navigate(folder.split('/').take(i + 1).join('/')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget searchField() => SizedBox(
    key: const ValueKey('archive-search'),
    height: 27,
    child: FTextField(
      control: FTextFieldControl.managed(controller: search),
      focusNode: searchFocus,
      size: FTextFieldSizeVariant.sm,
      hint: translateAppText('搜索', settings.locale.languageCode),
      style: const FTextFieldStyleDelta.delta(
        contentPadding: EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
      prefixBuilder: (_, _, _) => const Padding(
        padding: EdgeInsets.only(left: 8, right: 4),
        child: Icon(FIcons.search, size: 13, color: muted),
      ),
      clearable: (value) => value.text.isNotEmpty,
    ),
  );

  Widget browser() {
    final items = listingInFolder(folder);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (pointerSelectedItem) {
          pointerSelectedItem = false;
        } else {
          clearSelection();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: columns
                ? columnBrowser()
                : items.isEmpty
                ? Center(
                    child: AppText(
                      search.text.isEmpty ? '空文件夹' : '没有匹配的文件',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                : gallery
                ? galleryBrowser(items)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 560;
                      final rowIconSize = iconSize;
                      final rowHeight = rowExtent(rowIconSize);
                      final rowPadding = (rowIconSize * .25).clamp(3.0, 10.0);
                      if (grid) {
                        final margin = (iconSize * .1).clamp(4.0, 16.0);
                        final spacing = (iconSize * .08).clamp(4.0, 16.0);
                        final availableWidth =
                            (constraints.maxWidth - margin * 2).clamp(
                              1.0,
                              double.infinity,
                            );
                        gridColumns =
                            ((availableWidth + spacing) /
                                    (iconSize + 56 + spacing))
                                .floor()
                                .clamp(1, 1000);
                        final cellWidth =
                            (availableWidth - spacing * (gridColumns - 1)) /
                            gridColumns;
                        final displaySize = iconSize.clamp(
                          1.0,
                          (cellWidth - 24).clamp(1.0, double.infinity),
                        );
                        final textScaler = MediaQuery.textScalerOf(context);
                        final tileHeight =
                            displaySize +
                            (displaySize < 36 ? 13 : 27) +
                            textScaler.scale(displaySize < 36 ? 10 : 11) * 2.6 +
                            textScaler.scale(displaySize < 36 ? 9 : 10) * 1.3;
                        gridTileExtent = tileHeight;
                        gridPadding = margin;
                        gridSpacing = spacing;
                        return GridView.builder(
                          controller: listScroll,
                          scrollCacheExtent: ScrollCacheExtent.pixels(0),
                          addAutomaticKeepAlives: false,
                          padding: EdgeInsets.all(margin),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: gridColumns,
                                mainAxisExtent: tileHeight,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                              ),
                          itemCount:
                              items.length + (items.remainingCount > 0 ? 1 : 0),
                          itemBuilder: (_, i) => i == items.length
                              ? remainingItems(folder, items)
                              : tile(items[i], displaySize: displaySize),
                        );
                      }
                      final metadataWidth = compact
                          ? 0.0
                          : listSizeWidth + listModifiedWidth + listKindWidth;
                      final availableWidth =
                          (constraints.maxWidth - 2 * (rowPadding + listInset))
                              .clamp(160.0, double.infinity);
                      final nameWidth = listColumnWidth(
                        'name',
                        availableWidth - metadataWidth,
                      ).clamp(160.0, double.infinity);
                      final contentWidth = nameWidth + metadataWidth;
                      final listWidth =
                          contentWidth + 2 * (rowPadding + listInset);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: listWidth > constraints.maxWidth
                              ? listWidth
                              : constraints.maxWidth,
                          child: Column(
                            children: [
                              Container(
                                height: 27,
                                color: desktopColor(
                                  context,
                                  0xfff7f7f7,
                                  0xff292a2e,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: rowPadding + listInset,
                                ),
                                child: SizedBox(
                                  width: contentWidth,
                                  child: Row(
                                    children: [
                                      listHeaderCell('名称', 'name', nameWidth),
                                      if (!compact) ...[
                                        listHeaderCell(
                                          '大小',
                                          'size',
                                          listSizeWidth,
                                        ),
                                        listHeaderCell(
                                          '修改日期',
                                          'modified',
                                          listModifiedWidth,
                                        ),
                                        listHeaderCell(
                                          '种类',
                                          'kind',
                                          listKindWidth,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  controller: listScroll,
                                  scrollCacheExtent: ScrollCacheExtent.pixels(
                                    0,
                                  ),
                                  addAutomaticKeepAlives: false,
                                  padding: const EdgeInsets.all(listInset),
                                  itemExtent: rowHeight,
                                  itemCount:
                                      items.length +
                                      (items.remainingCount > 0 ? 1 : 0),
                                  itemBuilder: (_, i) => i == items.length
                                      ? remainingItems(folder, items)
                                      : row(
                                          items[i],
                                          compact,
                                          joinPrevious:
                                              i > 0 &&
                                              selectedPaths.contains(
                                                items[i - 1].path,
                                              ),
                                          joinNext:
                                              i + 1 < items.length &&
                                              selectedPaths.contains(
                                                items[i + 1].path,
                                              ),
                                          iconSize: rowIconSize,
                                          horizontalPadding: rowPadding,
                                          height: rowHeight,
                                          nameWidth: nameWidth,
                                          sizeWidth: compact
                                              ? null
                                              : listSizeWidth,
                                          modifiedWidth: compact
                                              ? null
                                              : listModifiedWidth,
                                          kindWidth: compact
                                              ? null
                                              : listKindWidth,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (document != null && !inspectorVisible) selectionStrip(),
        ],
      ),
    );
  }

  Widget crumb(String title, VoidCallback action) => DesktopButton(
    onPressed: busy ? null : action,
    flat: true,
    minHeight: 24,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    foreground: ink,
    child: Text(title),
  );
  IconData entryIcon(ArchiveEntry e) => e.directory
      ? CupertinoIcons.folder_fill
      : e.isImage
      ? CupertinoIcons.photo
      : CupertinoIcons.doc;
  Widget fileIcon(ArchiveEntry e, {double size = 22}) => Builder(
    builder: (context) => FutureBuilder<Uint8List?>(
      future: desktop.fileIcon(
        e.name,
        directory: e.directory,
        pixelSize: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
      builder: (_, snapshot) => snapshot.data == null
          ? Icon(
              entryIcon(e),
              size: size,
              color: e.directory
                  ? const Color(0xff6d9cbe)
                  : const Color(0xff858b92),
            )
          : Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
            ),
    ),
  );
  bool activeFileSelection(ArchiveEntry entry, {String? columnParent}) =>
      selectedPaths.contains(entry.path);

  Color entryForeground(
    ArchiveEntry entry, {
    bool secondary = false,
    String? columnParent,
  }) => activeFileSelection(entry, columnParent: columnParent)
      ? fileSelectionForeground(
          context,
          settings.selectionHighlight,
          secondary: secondary,
        )
      : selectedPaths.contains(entry.path)
      ? desktopSelectionForeground(context, secondary: secondary)
      : (secondary ? muted : Theme.of(context).colorScheme.onSurface);

  Widget listHeaderCell(String label, String column, double width) {
    final active = listSortColumn == column;
    return SizedBox(
      width: width,
      height: 27,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? null : () => sortList(column),
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Flexible(
                    child: AppText(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  if (active)
                    Icon(
                      listSortAscending
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 10,
                      color: muted,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: busy
                  ? null
                  : (details) => resizeListColumn(
                      column,
                      details.delta.dx,
                      currentWidth: width,
                    ),
              onHorizontalDragEnd: busy
                  ? null
                  : (_) => saveBrowsingPreferences(),
              child: const SizedBox(),
            ),
          ),
        ],
      ),
    );
  }

  Widget rowName(
    ArchiveEntry e,
    bool compact, {
    String? columnParent,
    double iconSize = 22,
  }) => Row(
    children: [
      fileIcon(e, size: iconSize),
      SizedBox(width: (iconSize * .25).clamp(3.0, 8.0)),
      Expanded(
        child: Text(
          e.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: entryForeground(e, columnParent: columnParent),
          ),
        ),
      ),
      if (columns && compact && e.directory)
        Icon(
          CupertinoIcons.chevron_right,
          size: 10,
          color: entryForeground(
            e,
            secondary: true,
            columnParent: columnParent,
          ),
        ),
      if (e.encrypted || !e.safe)
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(CupertinoIcons.lock, size: 13, color: muted),
        ),
    ],
  );

  Widget row(
    ArchiveEntry e,
    bool compact, {
    String? columnParent,
    bool joinPrevious = false,
    bool joinNext = false,
    double iconSize = 22,
    double horizontalPadding = 14,
    double height = 36,
    double? nameWidth,
    double? sizeWidth,
    double? modifiedWidth,
    double? kindWidth,
  }) => contextMenu(
    e,
    SizedBox(
      height: height,
      child: transferable(
        e,
        FileItemSurface(
          key: ValueKey('file-${e.path}'),
          name: e.name,
          activeSelection: activeFileSelection(e, columnParent: columnParent),
          selectionHighlight: settings.selectionHighlight,
          joinPrevious: selectedPaths.contains(e.path) && joinPrevious,
          joinNext: selectedPaths.contains(e.path) && joinNext,
          dividerInset: horizontalPadding,
          selected:
              selectedPaths.contains(e.path) ||
              (columns &&
                  e.directory &&
                  (folder == e.normalized ||
                      folder.startsWith('${e.normalized}/'))),
          onSelect: busy
              ? null
              : () {
                  if (columnParent != null) navigate(columnParent);
                  selectFromPointer(e);
                  if (columns) revealColumns();
                },
          onDragPrepare:
              widget.enableNativeTransfers && desktop.supportsQuickLook
              ? (frame) => prepareMacDrag(e, frame)
              : null,
          onDragStart:
              !busy && widget.enableNativeTransfers && desktop.supportsQuickLook
              ? () => startMacDrag(e)
              : null,
          onActivate: busy ? null : () => openEntry(e),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                if (nameWidth == null)
                  Expanded(
                    child: rowName(
                      e,
                      compact,
                      columnParent: columnParent,
                      iconSize: iconSize,
                    ),
                  )
                else
                  SizedBox(
                    width: nameWidth,
                    child: rowName(
                      e,
                      compact,
                      columnParent: columnParent,
                      iconSize: iconSize,
                    ),
                  ),
                if (!compact) ...[
                  SizedBox(
                    width: sizeWidth ?? 85,
                    child: AppText(
                      e.directory ? '—' : formatSize(e.size),
                      style: TextStyle(
                        fontSize: 11,
                        color: entryForeground(
                          e,
                          secondary: true,
                          columnParent: columnParent,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: modifiedWidth ?? 115,
                    child: AppText(
                      date(e.modified),
                      style: TextStyle(
                        fontSize: 11,
                        color: entryForeground(
                          e,
                          secondary: true,
                          columnParent: columnParent,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: kindWidth ?? 85,
                    child: AppText(
                      kind(e),
                      style: TextStyle(
                        fontSize: 11,
                        color: entryForeground(
                          e,
                          secondary: true,
                          columnParent: columnParent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    columnParent: columnParent,
  );
  Widget tile(ArchiveEntry e, {required double displaySize}) => contextMenu(
    e,
    transferable(
      e,
      FileItemSurface(
        key: ValueKey('file-${e.path}'),
        name: e.name,
        selectionHighlight: settings.selectionHighlight,
        selected: selectedPaths.contains(e.path),
        onSelect: busy
            ? null
            : () {
                selectFromPointer(e);
              },
        onDragPrepare: widget.enableNativeTransfers && desktop.supportsQuickLook
            ? (frame) => prepareMacDrag(e, frame)
            : null,
        onDragStart:
            !busy && widget.enableNativeTransfers && desktop.supportsQuickLook
            ? () => startMacDrag(e)
            : null,
        onActivate: busy ? null : () => openEntry(e),
        child: Padding(
          padding: EdgeInsets.all(displaySize < 36 ? 4 : 8),
          child: Column(
            children: [
              fileIcon(e, size: displaySize),
              SizedBox(height: displaySize < 36 ? 4 : 8),
              Text(
                e.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: displaySize < 36 ? 10 : 11,
                  height: 1.3,
                  color: entryForeground(e),
                ),
              ),
              SizedBox(height: displaySize < 36 ? 1 : 3),
              AppText(
                e.directory ? '文件夹' : formatSize(e.size),
                style: TextStyle(
                  fontSize: displaySize < 36 ? 9 : 10,
                  height: 1.3,
                  color: entryForeground(e, secondary: true),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget galleryBrowser(DirectoryListing items) {
    final doc = document!;
    return GalleryBrowser(
      document: doc,
      enabled: !busy && !closing,
      entries: items,
      trailing: items.remainingCount > 0 ? remainingItems(folder, items) : null,
      selected: selected,
      thumbnailSize: galleryIconSize,
      preview: previewContent(large: true, centerImage: true),
      loadImage: (entry) {
        if (closing || busy || document != doc) {
          return Future.error(StateError('画廊预览已取消'));
        }
        return service.preview(doc, entry);
      },
      icon: (entry, size) => fileIcon(entry, size: size),
      foreground: (entry) => entryForeground(entry),
      item: (entry, child) => contextMenu(
        entry,
        transferable(
          entry,
          FileItemSurface(
            key: ValueKey('file-${entry.path}'),
            name: entry.name,
            selected: selectedPaths.contains(entry.path),
            selectionHighlight: settings.selectionHighlight,
            onSelect: busy ? null : () => selectFromPointer(entry),
            onActivate: busy ? null : () => openEntry(entry),
            onDragPrepare:
                widget.enableNativeTransfers && desktop.supportsQuickLook
                ? (frame) => prepareMacDrag(entry, frame)
                : null,
            onDragStart:
                !busy &&
                    widget.enableNativeTransfers &&
                    desktop.supportsQuickLook
                ? () => startMacDrag(entry)
                : null,
            child: child,
          ),
        ),
      ),
    );
  }

  ArchiveDocument selectedDocument() {
    final doc = document!, roots = topLevelEntries(selection);
    return ArchiveDocument(
      doc.path,
      doc.entries
          .where(
            (entry) => roots.any(
              (root) =>
                  entry.path == root.path ||
                  (root.directory &&
                      entry.normalized.startsWith('${root.normalized}/')),
            ),
          )
          .toList(),
      doc.format,
      doc.writable,
      encoding: doc.encoding,
      resolvedEncoding: doc.resolvedEncoding,
    );
  }

  Future<void> openSelection() async {
    final entries = List<ArchiveEntry>.of(selection);
    for (final entry in entries.where((e) => !e.directory)) {
      if (entry.canExtract) await openEntry(entry);
    }
    final directory = entries.where((e) => e.directory).firstOrNull;
    if (directory != null) navigate(directory.normalized);
  }

  Widget selectionActions({bool compact = false}) {
    final entries = selection;
    final canOpen =
        !busy && entries.any((entry) => entry.directory || entry.canExtract);
    final open = entries.length == 1 && !entries.single.directory
        ? openButton(compact: compact)
        : DesktopButton(
            key: const ValueKey('selection-open'),
            onPressed: busy || entries.isEmpty ? null : openSelection,
            child: const AppText('打开'),
          );
    final extractButton = DesktopButton(
      key: const ValueKey('selection-extract'),
      onPressed: busy ? null : () => extract(onlySelected: entries.isNotEmpty),
      child: const AppText('解压'),
    );
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canOpen) ...[open, const SizedBox(width: 8)],
          extractButton,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canOpen) ...[open, const SizedBox(height: 8)],
        extractButton,
      ],
    );
  }

  Widget selectionStrip() => Container(
    key: const ValueKey('selection-strip'),
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        Expanded(
          child: selection.length > 1
              ? AppText(
                  '${selection.length} 个项目',
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  selected?.name ?? p.basename(document!.path),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        const SizedBox(width: 8),
        selectionActions(compact: true),
      ],
    ),
  );

  Widget openButton({bool compact = false}) {
    final split = desktop.supportsFileIntegration && selected != null;
    final label = selectedApplication == null
        ? '在默认应用中打开'
        : '用 ${selectedApplication!.name} 打开';
    final icon = selectedApplication?.icon;
    final content = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Image.memory(icon, width: 18, height: 18),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: AppText(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
    final button = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Flexible(
          child: DesktopButton(
            flat: split,
            onPressed: busy || selected == null
                ? null
                : () => openEntry(selected!),
            child: content,
          ),
        ),
        if (split) ...[
          SizedBox(
            height: 28,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: FTheme.of(context).colors.border,
            ),
          ),
          applicationPicker(selected!),
        ],
      ],
    );
    if (!split) return button;
    return Container(
      key: const ValueKey('selection-open-split'),
      decoration: BoxDecoration(
        color: FTheme.of(context).colors.background,
        border: Border.all(color: FTheme.of(context).colors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: button,
    );
  }

  String kind(ArchiveEntry e) => e.directory
      ? '文件夹'
      : e.isImage
      ? '图片'
      : e.isText
      ? '文本文档'
      : e.extension.isEmpty
      ? '文件'
      : '${e.extension.substring(1).toUpperCase()} 文件';
  String date(DateTime? d) => d == null
      ? '—'
      : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  Widget inspectorLayout(
    BoxConstraints constraints, {
    required Widget preview,
    required Widget information,
    required Widget actions,
  }) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 32).clamp(0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: gallery
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: gallery
                  ? [information]
                  : [
                      preview,
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: information,
                      ),
                    ],
            ),
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: actions,
        ),
      ),
    ],
  );

  Widget inspectorPanel() => Container(
    key: const ValueKey('inspector-panel'),
    decoration: BoxDecoration(
      color: gallery
          ? desktopColor(context, 0xfff5f5f7, 0xff2b2c2f)
          : desktopColor(context, 0xffffffff, 0xff202124),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (selection.length > 1) return selectionInspector(constraints);
        if (selected == null || selected!.directory) {
          return folderInspector(constraints, selected?.normalized ?? folder);
        }
        return inspectorLayout(
          constraints,
          preview: gallery
              ? const SizedBox()
              : Container(
                  key: const ValueKey('inspector-preview'),
                  height: (constraints.maxHeight * .5).clamp(120, 360),
                  padding: const EdgeInsets.all(8),
                  child: previewContent(),
                ),
          information: Column(
            key: const ValueKey('inspector-information'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (gallery)
                galleryInspectorSummary(
                  title: Text(
                    selected!.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: kind(selected!),
                  size: selected!.size,
                  icon: fileIcon(selected!, size: 48),
                )
              else ...[
                Text(
                  selected!.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                AppText(
                  kind(selected!),
                  style: TextStyle(
                    fontSize: 11,
                    color: desktopColor(context, 0xff777780, 0xffa0a0a5),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const AppText(
                '信息',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              info(
                '大小',
                selected!.directory ? '—' : formatSize(selected!.size),
              ),
              info('修改日期', date(selected!.modified)),
              info('路径', selected!.normalized),
            ],
          ),
          actions: selectionActions(),
        );
      },
    ),
  );
  Widget galleryInspectorSummary({
    required Widget title,
    required String subtitle,
    required int size,
    required Widget icon,
  }) => Padding(
    key: const ValueKey('inspector-summary'),
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 48, height: 56, child: Center(child: icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 4),
              DefaultTextStyle(
                style: TextStyle(fontSize: 11, color: muted),
                child: Wrap(
                  children: [AppText(subtitle), Text(' · ${formatSize(size)}')],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget selectionInspector(BoxConstraints constraints) {
    final entries = selection;
    final folders = entries.where((entry) => entry.directory).length;
    final roots = entries.where(
      (entry) => !entries.any(
        (parent) =>
            parent.directory &&
            parent.path != entry.path &&
            entry.normalized.startsWith('${parent.normalized}/'),
      ),
    );
    final size = roots.fold<int>(
      0,
      (sum, entry) =>
          sum +
          (entry.directory
              ? document!.index.sizes[entry.normalized] ?? 0
              : entry.size),
    );
    return inspectorLayout(
      constraints,
      preview: SizedBox(
        key: const ValueKey('inspector-preview'),
        height: (constraints.maxHeight * .5).clamp(120, 360),
        child: LayoutBuilder(
          builder: (_, bounds) => Stack(
            alignment: Alignment.center,
            children: [
              for (var i = entries.length.clamp(1, 3) - 1; i >= 0; i--)
                Transform.translate(
                  offset: Offset(i * 8.0, i * 8.0),
                  child: fileIcon(
                    entries[i],
                    size: bounds.biggest.shortestSide * .7,
                  ),
                ),
            ],
          ),
        ),
      ),
      information: Column(
        key: const ValueKey('inspector-information'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gallery)
            galleryInspectorSummary(
              title: AppText(
                '${entries.length} 个项目',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: '${entries.length - folders} 个文件、$folders 个文件夹',
              size: size,
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = entries.length.clamp(1, 3) - 1; i >= 0; i--)
                    Transform.translate(
                      offset: Offset(i * 3.0, i * 3.0),
                      child: fileIcon(entries[i], size: 36),
                    ),
                ],
              ),
            )
          else ...[
            AppText(
              '${entries.length} 个项目',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            AppText(
              '${entries.length - folders} 个文件、$folders 个文件夹',
              style: TextStyle(
                fontSize: 12,
                color: desktopColor(context, 0xff777780, 0xffa0a0a5),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const AppText(
            '信息',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          info('大小', formatSize(size)),
          info('项目', '${entries.length} 个'),
        ],
      ),
      actions: selectionActions(),
    );
  }

  Widget folderInspector(BoxConstraints constraints, String summaryFolder) {
    final archive = summaryFolder.isEmpty;
    final title = archive
        ? p.basename(document!.path)
        : p.posix.basename(summaryFolder);
    final entries = itemsInFolder(summaryFolder);
    final totalSize = archive
        ? document!.index.totalSize
        : document!.index.sizes[summaryFolder] ?? 0;
    final itemCount = archive
        ? document!.entries.length
        : document!.entries
              .where(
                (entry) =>
                    entry.normalized == summaryFolder ||
                    entry.normalized.startsWith('$summaryFolder/'),
              )
              .length;
    return inspectorLayout(
      constraints,
      preview: Container(
        key: const ValueKey('inspector-preview'),
        height: (constraints.maxHeight * .5).clamp(120, 360),
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, previewConstraints) => Center(
            child: fileIcon(
              ArchiveEntry(
                path: summaryFolder.isEmpty ? document!.path : summaryFolder,
                size: totalSize,
                directory: !archive,
              ),
              size: previewConstraints.biggest.shortestSide * .72,
            ),
          ),
        ),
      ),
      information: Column(
        key: const ValueKey('inspector-information'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gallery)
            galleryInspectorSummary(
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: archive ? document!.format : '文件夹',
              size: totalSize,
              icon: fileIcon(
                ArchiveEntry(
                  path: archive ? document!.path : summaryFolder,
                  size: totalSize,
                  directory: !archive,
                ),
                size: 48,
              ),
            )
          else ...[
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            AppText(
              archive ? document!.format : '文件夹',
              style: TextStyle(
                fontSize: 11,
                color: desktopColor(context, 0xff777780, 0xffa0a0a5),
              ),
            ),
          ],
          const SizedBox(height: 16),
          AppText(
            '信息',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          info('种类', archive ? document!.format : '文件夹'),
          info('项目', '$itemCount 个'),
          info('当前层级', '${entries.length} 个'),
          info('大小', formatSize(totalSize)),
          info('路径', archive ? document!.path : summaryFolder),
          if (archive) info('状态', document!.writable ? '可写入' : '只读'),
        ],
      ),
      actions: selectionActions(),
    );
  }

  Widget info(String label, String value) => Container(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).dividerColor, width: .5),
      ),
    ),
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 65,
          child: AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              color: desktopColor(context, 0xff777780, 0xffa0a0a5),
            ),
          ),
        ),
        Expanded(
          child: AppText(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, height: 1.5),
          ),
        ),
      ],
    ),
  );
  Widget previewContent({bool large = false, bool centerImage = false}) {
    final e = selected;
    if (e == null) return const SizedBox();
    if (previewError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AppText(
            previewError!,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ),
      );
    }
    if (e.directory || !(e.isImage || e.isText)) {
      return LayoutBuilder(
        builder: (context, constraints) => Center(
          child: fileIcon(e, size: constraints.biggest.shortestSide * .72),
        ),
      );
    }
    if (preview == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
        ),
      );
    }
    if (e.isImage) {
      return InteractiveViewer(
        alignment: centerImage ? Alignment.center : Alignment.topCenter,
        child: Image.memory(
          preview!,
          fit: BoxFit.contain,
          alignment: centerImage ? Alignment.center : Alignment.topCenter,
          errorBuilder: (_, _, _) => Center(child: fileIcon(e, size: 96)),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(large ? 20 : 12),
      child: SelectableText(
        previewText ?? '',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: large ? 13 : 10,
          height: 1.6,
          color: ink,
        ),
      ),
    );
  }

  Widget footer() {
    final data = feedback.data;
    final confirmation =
        data != null &&
        !data.running &&
        data.actions.keys.any((key) => key != 'dismiss');
    final tasks = taskQueue.tasks;
    final running = tasks.where((task) => task.running).firstOrNull;
    final active = data?.running == true ? data : null;
    final overallProgress = active?.progress ?? progress;
    final showProgress =
        overallProgress != null || active != null || running != null;
    final text = active != null
        ? '${appText(context, active.title)}${active.currentFile.isEmpty ? '' : ' · ${active.currentFile}'}${active.fileProgress == null ? '' : ' · ${appText(context, '当前文件')} ${(active.fileProgress!.clamp(0, 1) * 100).round()}%'}${overallProgress == null ? '' : ' · ${appText(context, '全部进度')} ${(overallProgress.clamp(0, 1) * 100).round()}%'}'
        : running != null
        ? '${appText(context, running.title)} · ${p.basename(running.archive)}'
        : data != null && !confirmation
        ? (data.detail.isEmpty
              ? appText(context, data.title)
              : appText(context, data.detail))
        : appText(context, status);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (confirmation)
          Container(
            key: const ValueKey('inline-task-actions'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: desktopColor(context, 0xfff6f6f6, 0xff292a2e),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  data.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entryNameInput != null)
                  TextField(
                    key: const ValueKey('inline-entry-name'),
                    controller: entryNameInput!,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => feedback.action('create'),
                  ),
                if (data.detail.isNotEmpty)
                  AppText(data.detail, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final action in data.actions.entries)
                      DesktopButton(
                        onPressed: () => feedback.action(action.key),
                        child: AppText(action.value),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (queueExpanded)
          Positioned(
            right: 8,
            bottom: 36,
            width: 360,
            child: Card(
              key: const ValueKey('archive-task-queue'),
              margin: EdgeInsets.zero,
              elevation: 8,
              clipBehavior: Clip.antiAlias,
              child: tasks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: AppText('队列为空', style: TextStyle(fontSize: 12)),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final task in tasks)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    task.running
                                        ? Icons.play_arrow
                                        : Icons.schedule,
                                    size: 14,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AppText(
                                      '${p.basename(task.archive)} · ${appText(context, task.title)}${task.cancelled ? ' · 正在取消' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey(
                                      'cancel-task-${task.archive}-${task.title}',
                                    ),
                                    tooltip: '取消任务',
                                    icon: const Icon(Icons.close, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 28,
                                      height: 28,
                                    ),
                                    onPressed: task.cancelled
                                        ? null
                                        : () => taskQueue.cancel(task),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: desktopColor(context, 0xfff6f6f6, 0xff292a2e),
            border: Border(
              top: BorderSide(
                color: desktopColor(context, 0xffdadada, 0xff414248),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: text,
                  child: Text(
                    text,
                    key: const ValueKey('archive-status'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: data?.error == true || statusError
                          ? const Color(0xffb44444)
                          : muted,
                    ),
                  ),
                ),
              ),
              if (showProgress) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: overallProgress?.clamp(0, 1),
                    minHeight: 3,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('task-queue-toggle'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => queueExpanded = !queueExpanded),
                child: AppText(
                  '队列 (${tasks.length})',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              if (document != null)
                SizedBox(
                  width: 132,
                  child: AppTooltip(
                    message: '调整图标大小',
                    child: DesktopSlider(
                      value: iconSize,
                      min: BrowsingPreferences.minIconSize(browsingView),
                      max: BrowsingPreferences.maxIconSize(browsingView),
                      onChanged: (value) {
                        setState(() => iconSize = value);
                        saveBrowsingPreferences();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
