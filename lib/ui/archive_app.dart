import 'app_localizations.dart';
import 'auxiliary_dialogs.dart';

import 'dart:async';
import 'dart:convert';

import 'archive_name_editor.dart';
import 'archive_comment_field.dart';
import 'archive_security_dialogs.dart';
import 'extraction_options_dialog.dart';
import '../models/archive_create_options.dart';
import '../models/finder_compression_request.dart';
import '../services/finder_compression.dart';
import '../models/archive_properties.dart';
import '../models/application_menu.dart';

import 'package:hizip_native/hizip_native.dart';
import 'package:nativeapi/nativeapi.dart' show NativeDocuments;

import '../services/archive_volumes.dart';
import '../services/rar_volumes.dart';

import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import '../services/platform_files.dart';
import '../services/harmony_bridge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/archive_entry.dart';
import '../models/browsing_preferences.dart';
import '../models/list_column_layout.dart';
import '../models/archive_index.dart';
import '../models/directory_listing.dart';
import '../models/preview_text.dart';
import '../models/preview_limit.dart';
import '../services/archive_service.dart';
import '../services/desktop_integration.dart';
import 'file_item_surface.dart';
import 'file_selection_area.dart';
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
import 'inline_properties_dialog.dart';
import 'breathing_status_bar.dart';
import '../services/archive_task_queue.dart';
import '../services/queued_archive_service.dart';
import '../models/task_feedback.dart';
import 'file_drop_target.dart';
import 'touch_file_drop_target.dart';
import '../services/file_transfer_clipboard.dart';

import 'package:super_drag_and_drop/super_drag_and_drop.dart';

const _selectionStripHeight = 40.0;

class FlatArchiveIcon extends StatelessWidget {
  const FlatArchiveIcon({
    super.key,
    required this.directory,
    required this.image,
    required this.width,
    required this.height,
  });

  final bool directory;
  final bool image;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: _FlatArchiveIconPainter(directory: directory, image: image),
  );
}

class _FlatArchiveIconPainter extends CustomPainter {
  const _FlatArchiveIconPainter({required this.directory, required this.image});

  final bool directory;
  final bool image;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    canvas.scale(scale, scale);
    final paint = Paint()..style = PaintingStyle.fill;
    if (directory) {
      paint.color = const Color(0xffffca28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 12, 40, 28),
          const Radius.circular(5),
        ),
        paint,
      );
      paint.color = const Color(0xffffa000);
      final tab = Path()
        ..moveTo(4, 12)
        ..lineTo(21, 12)
        ..lineTo(25, 16)
        ..lineTo(44, 16)
        ..lineTo(44, 21)
        ..lineTo(4, 21)
        ..close();
      canvas.drawPath(tab, paint);
    } else {
      paint.color = image ? const Color(0xff81d4fa) : const Color(0xff90caf9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(10, 4, 27, 40),
          const Radius.circular(4),
        ),
        paint,
      );
      paint.color = image ? const Color(0xff26a69a) : const Color(0xff1976d2);
      if (image) {
        canvas.drawCircle(
          const Offset(30, 13),
          4,
          Paint()..color = const Color(0xfffff59d),
        );
        final photo = Path()
          ..moveTo(12, 39)
          ..lineTo(21, 23)
          ..lineTo(27, 31)
          ..lineTo(31, 25)
          ..lineTo(36, 39)
          ..close();
        canvas.drawPath(photo, paint);
      } else {
        for (final y in [22.0, 29.0, 36.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(16, y, y == 36 ? 15 : 20, 3),
              const Radius.circular(1.5),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlatArchiveIconPainter oldDelegate) =>
      oldDelegate.directory != directory || oldDelegate.image != image;
}

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
    this.propertiesData,
    this.propertiesAction,
    this.propertiesWindowFactory,
  });
  final FileTransferClipboard? clipboard;
  final bool enableNativeTransfers;
  final AppSettings? settings;
  final ArchiveService? service;
  final DesktopIntegration? desktop;
  final ArchiveDocument? initialDocument;
  final Map<String, dynamic>? propertiesData;
  final PropertiesWindowAction? propertiesAction;
  final PropertiesWindowTransport Function()? propertiesWindowFactory;
  @override
  State<ArchiveWorkspace> createState() => _ArchiveWorkspaceState();
}

class _ArchiveWorkspaceState extends State<ArchiveWorkspace>
    with WidgetsBindingObserver {
  Color get muted => context.theme.colors.mutedForeground;

  static const listInset = 6.0;
  final contentScaffold = GlobalKey<ScaffoldState>();
  late final settings = widget.settings ?? AppSettings.instance;
  final taskQueue = ArchiveTaskQueue();
  late final service = QueuedArchiveService(
    widget.service ?? ArchiveService(),
    taskQueue,
    authorize: desktop.authorizeFileAccess,
  );
  bool queueExpanded = false;
  TextEditingController? entryNameInput;
  ArchiveEntry? renamingEntry;
  ArchiveDocument? renamingDocument;
  bool renameDialogOpen = false;
  final commentDrafts = <String, ArchiveCommentDraft>{};
  final propertiesWindows = <String, PropertiesWindowTransport>{};
  Map<String, dynamic>? propertyWindowData;
  String? propertyActionError;
  int runningOperations = 0;
  late final desktop = widget.desktop ?? DesktopIntegration();
  late final clipboard = widget.clipboard ?? FileTransferClipboard();
  final selectedPaths = <String>{};
  bool marqueeSelecting = false;
  final expandedListings = <(String, String)>{};
  final transferExports = <String, Future<List<String>>>{};
  final fileFocus = FocusNode(debugLabel: 'archive files');
  final searchFocus = FocusNode(debugLabel: 'archive search');
  bool compactSearchOpen = false;
  bool menuTextEditing = false;
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
  double listColumnDragStart = 0;
  ListColumnLayout? listColumnDragLayout;
  bool columns = false, gallery = false, inspectorVisible = false;
  final expandedFolders = <String>{''};
  ArchiveFolder folderTree = ArchiveFolder('');
  DefaultApplication? selectedApplication;
  String? applicationMenuName;
  List<FileApplication> menuApplications = [];
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
    final textHeight = (MediaQuery.textScalerOf(context).scale(12) * 1.3)
        .ceilToDouble();
    final height =
        (size > textHeight ? size : textHeight) +
        2 * (size * .16).clamp(2.0, 6.0);
    return height;
  }

  bool openingSystemPreview = false;
  (ArchiveDocument, List<ArchiveEntry>)? activeDrag, armedDrag;
  (ArchiveDocument, List<ArchiveEntry>)? touchDrag;
  DateTime? activeDragStartedAt;
  final touchDrops = TouchFileDropController();
  final search = TextEditingController();
  final recent = <String>[];
  Set<String>? availableCreateFormats;
  Iterable<MapEntry<String, String>> get createFormats => writableArchiveFormats
      .entries
      .where((entry) => availableCreateFormats?.contains(entry.key) ?? true);
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
  String? acknowledgedAttention;
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
  Timer? searchTimer;
  int searchRequest = 0;
  List<ArchiveEntry>? searchResults;
  String? searchedFolder, searchedTerm;
  ArchiveDocument? searchedDocument;
  int sidebarRevision = 0;
  String? previewError;
  int previewRequest = 0;
  Timer? timer;
  final pending = <OpenedArchiveFile>[];
  Color get ink => Theme.of(context).colorScheme.onSurface;
  late final feedback = TaskFeedbackController(
    settings: settings,
    allowNativeWindow: () =>
        entryNameInput == null && MediaQuery.sizeOf(context).width >= 800,
    progressDelay: Duration.zero,
  );
  @override
  void initState() {
    super.initState();
    setWindowClosePreparation(prepareToClose);
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
    // Older fixed Name widths no longer override the elastic column.
    listNameWidth = 0;
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
    if (widget.propertiesData != null) {
      applyPropertiesData(widget.propertiesData!);
      return;
    }
    NativeDocuments.listenForOpenFiles((paths) async {
      for (final path in paths) {
        if (mounted && !closing) await loadArchive(path);
      }
    });
    desktop.listen(
      navigate: (delta) => moveSelection(delta, fromQuickLook: true),
      prepareClose: prepareToClose,
      dragEnded: () {
        final drag = activeDrag;
        activeDrag = null;
        final showFeedback = dragResultNeedsFeedback();
        if (mounted && drag != null && !busy && !closing) {
          message(
            desktop.lastDragSucceeded == false
                ? '拖拽已取消'
                : '拖拽完成：${drag.$2.length} 个项目',
            showFeedback: desktop.lastDragSucceeded == false || showFeedback,
          );
        }
      },
      dragStarted: () {
        activeDrag = armedDrag;
        activeDragStartedAt = DateTime.now();
        feedback.action('dismiss');
      },
      command: handleMenuCommand,
      openArchive: loadArchive,
      compressFiles: receiveFinderCompression,
      clearRecent: () => setState(recent.clear),
    );
    unawaited(initializeArchives());
    FocusManager.instance.addListener(syncFileCommands);
    searchFocus.addListener(searchFocusChanged);
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
    unawaited(loadCreateCapabilities());
  }

  Future<void> loadCreateCapabilities() async {
    try {
      final capability = await service.capabilities();
      if (mounted) {
        setState(
          () => availableCreateFormats = Set<String>.from(
            capability['writableFormats'] as List,
          ),
        );
      }
    } catch (_) {
      // The create action still checks the engine before starting a write.
    }
  }

  @override
  void dispose() {
    if (widget.propertiesData == null) NativeDocuments.listenForOpenFiles(null);
    setWindowClosePreparation(null);
    for (final window in propertiesWindows.values) {
      window.dispose();
    }
    for (final draft in commentDrafts.values) {
      draft.dispose();
    }
    settings.removeListener(applySettings);
    FocusManager.instance.removeListener(syncFileCommands);
    feedback.dispose();
    touchDrops.dispose();
    taskQueue.removeListener(queueChanged);
    timer?.cancel();
    statusResetTimer?.cancel();
    searchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.propertiesData == null) {
      unawaited(desktop.enableFileCommands(false));
      desktop.dispose();
    }
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
    final language = settings.locale.languageCode;
    unawaited(
      desktop.setLanguage(
        language,
        translations: {
          for (final text in appEnglishMessages.keys)
            text: translateAppText(text, language),
        },
        english: appEnglishMessages,
      ),
    );
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

  void resizeListColumn(
    String column,
    double delta, {
    required ListColumnLayout layout,
  }) {
    final resized = (listColumnDragLayout ?? layout)
        .withAvailableWidth(layout.availableWidth)
        .resizeBoundary(column, delta);
    setState(() {
      listNameWidth = 0;
      listSizeWidth = resized.size;
      listModifiedWidth = resized.modified;
      listKindWidth = resized.kind;
    });
  }

  void finishListColumnResize() {
    listColumnDragLayout = null;
    saveBrowsingPreferences();
  }

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
    if (auxiliaryModalDepth.value > 0) return;
    if (invokeTextMenuCommand(command)) return;
    if (command == 'settings') {
      openSettings();
      return;
    }
    final item = menuCommandItem(command);
    if (item == null || !item.enabled) return;
    if (command == 'copy') copyFiles();
    if (command == 'paste') pasteFiles();
    if (command == 'selectAll') selectAllFiles();
    if (command == 'open') openCommand();
    if (command == 'openArchive') pickArchive();
    if (command == 'openSelection') openSelection();
    if (command == 'openInHiZip' && selected != null) openEntry(selected!);
    if (command == 'chooseApplication' && selected != null) {
      chooseOpenApplication(selected!);
    }
    if (command.startsWith('openWith:') && selected != null) {
      final path = command.substring(9);
      final app = menuApplications.where((app) => app.path == path).firstOrNull;
      if (app != null) openEntry(selected!, application: app);
    }
    if (command.startsWith('recent:')) loadArchive(command.substring(7));
    if (command == 'clearRecent') setState(recent.clear);
    if (command == 'saveCopy') saveArchiveCopy();
    if (command == 'quickZip') quickCreateZip();
    if (command == 'create') createArchive(chooseFormat: true);
    if (command.startsWith('create:')) {
      createArchive(format: command.substring(7));
    }
    if (command == 'closeArchive') closeTab(document?.path);
    if (command == 'extract') extract();
    if (command == 'extractNamed') extract(namedFolder: true);
    if (command == 'extractSelection') extract(onlySelected: true);
    if (command == 'extractFolder') extract(currentFolder: true);
    if (command == 'addFiles') addFiles();
    if (command == 'addFolder') addFiles(directory: true);
    if (command == 'moveTo') transferSelection(move: true);
    if (command == 'copyTo') transferSelection(move: false);
    if (command == 'newFolder') newEntry(directory: true);
    if (command == 'newDocument') newEntry();
    if (command == 'rename') renameSelection();
    if (command == 'verify') verifyArchive();
    if (command == 'properties') showProperties();
    if (command == 'archiveProperties') showProperties(archiveOverview: true);
    if (command == 'quickLook') quickLook();
    if (command == 'search') openSearch();
    if (command == 'back') goBack();
    if (command == 'enclosingFolder') {
      navigate(p.posix.dirname(folder) == '.' ? '' : p.posix.dirname(folder));
    }
    if (command == 'archiveRoot') navigate('');
    if (command == 'previousTab' || command == 'nextTab') {
      final index = tabs.indexWhere(
        (tab) => tab.document.path == document?.path,
      );
      final delta = command == 'nextTab' ? 1 : -1;
      switchTab(tabs[(index + delta) % tabs.length]);
    }
    if (command == 'tasks') setState(() => queueExpanded = !queueExpanded);
    if (command.startsWith('sort:')) {
      setState(() => listSortColumn = command.substring(5));
      saveBrowsingPreferences();
    }
    if (command == 'ascending' || command == 'descending') {
      setState(() => listSortAscending = command == 'ascending');
      saveBrowsingPreferences();
    }
    if (command == 'largerIcons' || command == 'smallerIcons') {
      setState(() {
        iconSize = (iconSize + (command == 'largerIcons' ? 4 : -4)).clamp(
          BrowsingPreferences.minIconSize(browsingView),
          BrowsingPreferences.maxIconSize(browsingView),
        );
      });
      saveBrowsingPreferences();
    }
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

  bool invokeTextMenuCommand(String command) {
    final focus = FileContextMenu.commandFocus?.context;
    if (focus == null ||
        !focus.mounted ||
        focus.findAncestorStateOfType<EditableTextState>() == null) {
      return false;
    }
    final Intent? intent = switch (command) {
      'undo' => const UndoTextIntent(SelectionChangedCause.toolbar),
      'redo' => const RedoTextIntent(SelectionChangedCause.toolbar),
      'cut' => const CopySelectionTextIntent.cut(SelectionChangedCause.toolbar),
      'copy' => CopySelectionTextIntent.copy,
      'paste' => const PasteTextIntent(SelectionChangedCause.toolbar),
      'selectAll' => const SelectAllTextIntent(SelectionChangedCause.toolbar),
      _ => null,
    };
    if (intent == null) return false;
    Actions.maybeInvoke(focus, intent);
    return true;
  }

  ApplicationMenuItem? menuCommandItem(String command) {
    ApplicationMenuItem? find(List<ApplicationMenuItem> items) {
      for (final item in items) {
        if (item.command == command) return item;
        if (item.children != null) {
          final result = find(item.children!);
          if (result != null) return result;
        }
      }
      return null;
    }

    return find(applicationMenus);
  }

  void openSearch() {
    setState(() => compactSearchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && compactSearchOpen) searchFocus.requestFocus();
    });
  }

  Future<void> addFiles({bool directory = false}) async {
    try {
      final paths = directory
          ? [if (await getDirectoryPath() case final String path) path]
          : (await openFiles()).map((file) => file.path).toList();
      if (!mounted || paths.isEmpty || closing) return;
      await receiveFiles(paths, folder);
    } catch (error) {
      if (mounted) message(error.toString(), error: true);
    }
  }

  bool acceptsSelectionDestination(String path, List<ArchiveEntry> entries) =>
      !entries.any(
        (entry) =>
            entry.directory &&
            (path == entry.normalized ||
                path.startsWith('${entry.normalized}/')),
      ) &&
      !entries.every(
        (entry) =>
            (p.posix.dirname(entry.normalized) == '.'
                ? ''
                : p.posix.dirname(entry.normalized)) ==
            path,
      );

  Future<void> transferSelection({required bool move}) async {
    final doc = document;
    final entries = topLevelEntries(selection);
    if (doc == null || !doc.writable || entries.isEmpty || busy || closing) {
      return;
    }
    final folders =
        [
              '',
              ...doc.index.byNormalized.values
                  .where((entry) => entry.directory)
                  .map((entry) => entry.normalized),
            ]
            .where((path) => acceptsSelectionDestination(path, entries))
            .toSet()
            .toList()
          ..sort();
    if (folders.isEmpty) return;
    final target = await showAuxiliaryDialog<String>(
      context: context,
      settings: settings,
      kind: 'transfer',
      data: {'move': move, 'folders': folders},
      decodeResult: (data) => data['value'] as String?,
      builder: (_) => ArchiveTransferDialog(move: move, folders: folders),
    );
    if (target == null || !mounted || document != doc || busy || closing) {
      return;
    }
    await run(() async {
      final result = await service.transferEntries(
        doc,
        entries,
        target,
        move: move,
      );
      refreshDocument(result);
      navigate(target);
      message(move ? '已移动 ${entries.length} 个项目' : '已复制 ${entries.length} 个项目');
    }, title: move ? '正在移动文件' : '正在复制文件');
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
      if (await showSettingsWindow(
        settings,
        forceInline: MediaQuery.sizeOf(context).width < 800,
      )) {
        return;
      }
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
    if (taskQueue.tasks.any((task) => task.running && task.cancelled) &&
        feedback.reply != null) {
      feedback.action('cancel');
    }
    if (mounted) setState(() {});
  }

  Future<void> run(
    Future<void> Function() work, {
    String title = '正在处理文件',
    bool showProgress = true,
    bool reportSuccess = true,
    bool reportFastSuccess = true,
    String? archivePath,
  }) async {
    if (closing || !mounted) return;
    try {
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
          reportFastSuccess: reportSuccess && reportFastSuccess,
          progressDelay: reportFastSuccess
              ? null
              : const Duration(milliseconds: 500),
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
            if (e is ArchiveOperationCancelled || e is ArchiveTaskCancelled) {
              message('操作已取消');
            } else {
              message(
                e.toString().replaceFirst('Bad state: ', ''),
                error: true,
              );
            }
          }
          rethrow;
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
      }, retryable: true);
    } catch (_) {
      /* Failure is shown and remains in the task list when retryable. */
    }
  }

  Future<T> observed<T>(
    String title,
    Future<T> Function() work, {
    required String success,
    bool Function()? current,
    bool reportFastSuccess = true,
    bool reportSuccess = true,
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
        progressDelay: reportFastSuccess
            ? null
            : const Duration(milliseconds: 500),
        current: () => mounted && (current?.call() ?? true),
      );
      try {
        final result = await work();
        if (mounted && (current?.call() ?? true)) {
          if (reportSuccess) {
            feedback.result(success, token: token);
          } else if (token == feedback.generation) {
            feedback.action('dismiss');
          }
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
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '压缩文件',
          extensions: readableArchivePickerExtensions,
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
    cancelRename(focus: false);
    if (save) saveActiveTab();
    clearPreparedDrag();
    transferExports.clear();
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
    revealCurrentPath();
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
          await desktop.closeQuickLook();
        }
        await service.closeArchive(tab.document.path);
        if (!mounted) return;
        pending.removeWhere((file) => file.archive == path);
        setState(() {
          tabs.remove(tab);
          commentDrafts.remove(tab.document.path)?.dispose();
        });
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
    if (ArchiveVolumes.isVolume(path)) path = ArchiveVolumes.firstPath(path);
    if (RarVolumes.isRarPath(path)) path = RarVolumes.firstPath(path);
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
          ArchiveDocument? result;
          try {
            result = await service.read(path);
          } catch (error) {
            if (!RegExp(
              'password|passphrase|encrypted',
              caseSensitive: false,
            ).hasMatch(error.toString())) {
              rethrow;
            }
          }
          if (result == null ||
              (result.entries.any((entry) => entry.encrypted) &&
                  result.password.isEmpty)) {
            if (!mounted) return;
            final unlocked = await showAuxiliaryDialog<bool>(
              context: context,
              settings: settings,
              kind: 'password',
              data: const {},
              decodeResult: (data) => data['value'] as bool?,
              onAction: (action, data) async {
                result = await service.readWithPassword(
                  path,
                  data['password'] as String,
                );
                return {};
              },
              barrierDismissible: false,
              builder: (_) => ArchivePasswordDialog(
                onUnlock: (password) async {
                  result = await service.readWithPassword(path, password);
                },
              ),
            );
            if (unlocked != true) return;
          }
          final openedDocument = result!;
          if (!mounted) return;
          saveActiveTab();
          final previousIndex = existing == null ? -1 : tabs.indexOf(existing);
          if (existing != null) {
            if (!ArchiveVolumes.isVolume(path)) {
              await service.closeArchive(path);
            }
            pending.removeWhere((file) => file.archive == path);
            tabs.remove(existing);
          }
          final tab = _ArchiveTab(openedDocument);
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

  Future<void> finderCompressionQueue = Future.value();

  Future<void> saveArchiveCopy() async {
    final doc = document;
    if (doc == null || busy || closing) return;
    await checkChanges();
    if (!mounted || document != doc) return;
    await savePropertyDrafts();
    await run(
      () async {
        if (await HarmonyBridge.exportFile(doc.path)) {
          message('压缩包已保存');
        }
      },
      title: '正在保存压缩包',
      archivePath: doc.path,
    );
  }

  Future<void> quickCreateZip() async {
    try {
      final paths = await desktop.selectCompressionContents();
      if (!mounted || closing || paths.isEmpty) return;
      await receiveFinderCompression(
        FinderCompressionRequest(paths: paths, quickZip: true),
      );
    } catch (error) {
      if (mounted) message(error.toString(), error: true);
    }
  }

  Future<void> receiveFinderCompression(FinderCompressionRequest request) {
    final next = finderCompressionQueue.then((_) async {
      if (!mounted || closing) return;
      try {
        if (!await desktop.authorizeFileAccess(
          readPaths: request.paths,
          writeDirectories: request.quickZip
              ? [p.dirname(request.paths.first)]
              : const [],
        )) {
          return;
        }
        if (!mounted || closing) return;
        if (request.quickZip) {
          var target = await availableFinderArchivePath(request.paths, 'zip');
          if (HarmonyBridge.supported) {
            final location = await getSaveLocation(
              suggestedName: p.basename(target),
            );
            if (location == null) return;
            target = location.path;
          }
          await run(
            () async {
              await createFinderQuickZip(
                service,
                request.paths,
                output: target,
              );
              if (HarmonyBridge.supported) {
                await HarmonyBridge.finishSave(target);
              }
              message('压缩包已创建');
            },
            title: '正在创建压缩包',
            archivePath: target,
          );
        } else {
          await createArchive(sourcePaths: request.paths, chooseFormat: true);
        }
      } catch (error) {
        if (mounted) message(error.toString(), error: true);
      }
    });
    finderCompressionQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> createArchive({
    String format = 'zip',
    bool empty = false,
    List<String>? sourcePaths,
    bool chooseFormat = false,
  }) async {
    if (!writableArchiveFormats.containsKey(format)) return;
    var files = empty ? <String>[] : List<String>.of(sourcePaths ?? []);
    late Map<String, dynamic> capability;
    try {
      capability = await service.capabilities();
    } catch (error) {
      if (mounted) message(error.toString(), error: true);
      return;
    }
    if (!mounted) return;
    final supported = List<String>.from(capability['writableFormats'] as List);
    if (!supported.contains(format)) {
      message('当前引擎不支持此压缩格式。', error: true);
      return;
    }
    String? output;
    if (!mounted || closing) return;
    final Map<String, String> creationFormats = chooseFormat
        ? {
            for (final entry in writableArchiveFormats.entries)
              if (supported.contains(entry.key) &&
                  !const [
                    'gz',
                    'bz2',
                    'xz',
                    'lzma',
                    'zst',
                    'lz4',
                    'lzip',
                    'Z',
                  ].contains(entry.key))
                entry.key: entry.value,
          }
        : const {};
    final options = await showAuxiliaryDialog<ArchiveCreateOptions>(
      context: context,
      settings: settings,
      kind: 'create',
      data: {
        'format': format,
        'aesAvailable': capability['zipAES256'] == true,
        'empty': empty,
        'initialLevel': settings.archive.compressionLevel,
        'initialNestInFolder': files.length > 1,
        'paths': files,
        'output': output ?? '',
        'formats': creationFormats,
      },
      decodeResult: (data) {
        files = List<String>.from(data['paths'] as List);
        output = data['output'] as String;
        return ArchiveCreateOptions.fromJson(
          Map<String, dynamic>.from(data['options'] as Map),
        );
      },
      builder: (_) => ArchiveCreateDialog(
        format: format,
        aesAvailable: capability['zipAES256'] == true,
        empty: empty,
        initialLevel: settings.archive.compressionLevel,
        initialNestInFolder: files.length > 1,
        initialPaths: files,
        initialOutputPath: output ?? '',
        selectContents: ({bool foldersOnly = false}) =>
            desktop.selectCompressionContents(foldersOnly: foldersOnly),
        suggestOutputPath: availableFinderArchivePath,
        selectOutputPath: selectArchiveOutputPath,
        onSelectionConfirmed: (paths, path) {
          files = paths;
          output = path;
        },
        formats: creationFormats,
      ),
    );
    if (options == null || output == null || !mounted || closing) return;
    var target = output!;
    String? volumeRoot;
    if (HarmonyBridge.supported && options.volumeSize > 0) {
      volumeRoot = await getDirectoryPath();
      if (volumeRoot == null || !mounted || closing) return;
      target = p.join(volumeRoot, p.basename(target));
    }
    if (HarmonyBridge.supported &&
        volumeRoot == null &&
        !await NativeDocuments.hasSaveLocation(target)) {
      final location = await getSaveLocation(suggestedName: p.basename(target));
      if (location == null || !mounted || closing) return;
      target = location.path;
    }
    if (!await desktop.authorizeFileAccess(
          readPaths: files,
          writeDirectories: [p.dirname(target)],
        ) ||
        !mounted ||
        closing) {
      return;
    }
    var created = false;
    await run(
      () async {
        await service.createWithOptions(target, files, options);
        if (HarmonyBridge.supported) {
          if (volumeRoot == null) {
            await HarmonyBridge.finishSave(target);
          } else {
            await HarmonyBridge.finishDirectory(volumeRoot, volumeRoot);
          }
        }
        created = true;
        message('压缩包已创建');
      },
      title: '正在创建压缩包',
      archivePath: target,
    );
    if (created) {
      await loadArchive(
        options.volumeSize > 0 ? '$target.001' : target,
        encoding: settings.archive.createEncoding,
      );
    }
  }

  void navigate(String next, {bool back = false}) {
    if (next == folder) return;
    cancelRename(focus: false);
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
    revealCurrentPath();
    ensureGallerySelection();
  }

  void revealCurrentPath() {
    final archivePath = document?.path;
    final currentFolder = folder;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          document?.path != archivePath ||
          folder != currentFolder ||
          !pathScroll.hasClients) {
        return;
      }
      pathScroll.jumpTo(pathScroll.position.maxScrollExtent);
    });
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
        reportSuccess: false,
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
        if (application != null) {
          await desktop.openWithAccess(
            f.path,
            application,
            writable: doc.writable,
          );
        }
        if (!doc.writable) {
          message('已以只读模式打开。编辑时请另存到其他位置。');
        } else {
          message(
            application == null
                ? '已在默认应用中打开 · 修改检测已开启'
                : '已用 ${application.name} 打开 · 修改检测已开启',
          );
        }
      },
      title: '正在打开文件',
      archivePath: doc.path,
    );
  }

  Future<void> extract({
    bool onlySelected = false,
    bool namedFolder = false,
    bool currentFolder = false,
  }) async {
    final doc = document;
    if (doc == null || closing) return;
    final extractionDoc = doc;
    final folderRoot = currentFolder ? doc.index.byNormalized[folder] : null;
    if (currentFolder && (folderRoot == null || !folderRoot.directory)) return;
    // A selection extracts its own roots directly into the destination. So
    // does the whole archive, unless the caller asked for it to land inside
    // a folder named after the archive (roots: null lets the service pick
    // and auto-dedupe that name) — the two never combine in this app's UI.
    final extractionRoots = folderRoot != null
        ? [folderRoot]
        : onlySelected && selection.isNotEmpty
        ? topLevelEntries(selection)
        : namedFolder
        ? null
        : topLevelEntries(doc.entries);
    final target = await getDirectoryPath(
      confirmButtonText: translateAppText(
        '解压到这里',
        settings.locale.languageCode,
      ),
    );
    if (target == null || !mounted) return;
    final conflictPolicy = await showAuxiliaryDialog<ExtractionConflictPolicy>(
      context: context,
      settings: settings,
      kind: 'extraction',
      data: const {},
      decodeResult: (data) =>
          ExtractionConflictPolicy.values.byName(data['value'] as String),
      builder: (_) => const ExtractionOptionsDialog(),
    );
    if (conflictPolicy == null || !mounted) return;
    var linkPolicy = LinkPolicy.keepAll;
    final unsafeLinks = unsafeLinksFor(extractionDoc, extractionRoots);
    if (unsafeLinks.isNotEmpty) {
      final example = unsafeLinks.first;
      final situation = '发现 ${unsafeLinks.length} 个指向绝对路径或解压目录之外的符号链接';
      setState(() {
        status = situation;
        statusError = false;
      });
      final choice = await feedback.ask(
        TaskFeedback(
          title: '压缩包含有可能不安全的符号链接',
          detail:
              '$situation，例如 ${example.path} → ${example.linkTarget}。\n\n保留后，解压出的链接会指向压缩包之外的位置。',
          actions: const {'keep': '保留链接', 'skip': '跳过这些链接', 'cancel': '取消'},
        ),
      );
      if (!mounted) return;
      if (choice == null || choice == 'cancel') {
        setState(() => status = defaultStatus());
        return;
      }
      if (choice == 'skip') linkPolicy = LinkPolicy.skipUnsafe;
      setState(() => status = defaultStatus());
    }
    var caseConflictPolicy = CaseConflictPolicy.rename;
    late List<ArchiveEntry> clashes;
    try {
      clashes = await service.caseConflicts(
        extractionDoc,
        target,
        roots: extractionRoots,
      );
    } on ArchiveTaskCancelled {
      return;
    } catch (error) {
      if (mounted) message(error.toString(), error: true);
      return;
    }
    if (!mounted) return;
    if (clashes.isNotEmpty) {
      final situation = '有 ${clashes.length} 个文件仅大小写不同，目标磁盘不区分大小写';
      setState(() {
        status = situation;
        statusError = false;
      });
      final choice = await feedback.ask(
        TaskFeedback(
          title: '文件名仅大小写不同',
          detail:
              '$situation，例如 ${clashes.first.path}。\n\n自动重命名会保留两个文件（后者加上“ (2)”），跳过则只保留第一个。',
          actions: const {'rename': '自动重命名', 'skip': '跳过后者', 'cancel': '取消'},
        ),
      );
      if (!mounted) return;
      if (choice == null || choice == 'cancel') {
        setState(() => status = defaultStatus());
        return;
      }
      if (choice == 'skip') caseConflictPolicy = CaseConflictPolicy.skip;
      setState(() => status = defaultStatus());
    }
    final notices = <String>[];
    await run(
      () async {
        if (tabFor(doc.path) == null) return;
        final output = await service.extract(
          extractionDoc,
          target,
          roots: extractionRoots,
          linkPolicy: linkPolicy,
          caseConflictPolicy: caseConflictPolicy,
          notice: notices.add,
          conflictPolicy: conflictPolicy,
          resolveConflict: (path) async {
            final choice = await feedback.ask(
              TaskFeedback(
                title: '目标项目已存在',
                detail: path,
                actions: const {
                  'overwrite': '覆盖',
                  'skip': '跳过',
                  'rename': '自动重命名',
                  'cancel': '取消',
                },
              ),
            );
            return switch (choice) {
              'overwrite' => ExtractionConflictPolicy.overwrite,
              'skip' => ExtractionConflictPolicy.skip,
              'rename' => ExtractionConflictPolicy.rename,
              _ => null,
            };
          },
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
        final destination = HarmonyBridge.supported
            ? await HarmonyBridge.finishDirectory(target, output)
            : output;
        if (notices.isEmpty) {
          message('解压完成：$destination');
        } else {
          // Kept on screen and pulsing until the user acknowledges it.
          message(
            '解压完成，但${notices.join('；')}：$destination',
            error: true,
            showFeedback: false,
          );
        }
      },
      title: '正在解压',
      reportFastSuccess: false,
      archivePath: doc.path,
      showProgress: true,
    );
  }

  List<ArchiveEntry> unsafeLinksFor(
    ArchiveDocument doc,
    List<ArchiveEntry>? roots,
  ) => doc.entries
      .where(
        (e) =>
            e.hasUnsafeLink &&
            (roots == null ||
                roots.any(
                  (r) =>
                      e.path == r.path ||
                      (r.directory &&
                          e.normalized.startsWith('${r.normalized}/')),
                )),
      )
      .toList();

  void acknowledgeStatus(String key) {
    statusResetTimer?.cancel();
    if (feedback.data?.error == true) feedback.action('dismiss');
    setState(() {
      if (statusError) {
        statusError = false;
        status = defaultStatus();
      }
      acknowledgedAttention = key;
    });
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
    final source = itemsInFolder(path);
    // The index and filtered search results already have the default order.
    if (listSortColumn == 'name' && listSortAscending) return source;
    final entries = List<ArchiveEntry>.of(source);
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
    sortedListItems(path),
    expanded: expandedListings.contains(listingKey(path)),
  );

  List<ArchiveEntry> get visibleItems => listingInFolder(folder);

  Widget remainingItems(String path, DirectoryListing listing) =>
      FileItemSurface(
        key: ValueKey('expand-remaining-$path'),
        name: translateAppText(
          '双击展开剩余 ${listing.remainingCount} 项',
          settings.locale.languageCode,
        ),
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
              style: TextStyle(fontSize: 12, color: muted),
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

  void searchFocusChanged() {
    syncFileCommands();
    if (mounted && compactSearchOpen && !searchFocus.hasFocus) {
      setState(() => compactSearchOpen = false);
    }
  }

  void syncFileCommands() {
    unawaited(desktop.enableFileCommands(fileFocus.hasPrimaryFocus));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FileContextMenu.commandFocus?.context;
      final textEditing =
          focus != null &&
          focus.mounted &&
          focus.findAncestorStateOfType<EditableTextState>() != null;
      if (textEditing != menuTextEditing) {
        setState(() => menuTextEditing = textEditing);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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

  Widget fileSelectionArea(
    Widget child,
    ScrollController controller, {
    String? parent,
  }) => FileSelectionArea(
    key: ValueKey(
      'file-selection-area-${document?.path}-${parent ?? folder}-$browsingView',
    ),
    enabled: !busy && !closing && renamingEntry == null,
    scrollController: controller,
    selectedPaths: selectedPaths,
    onStart: () {
      fileFocus.requestFocus();
      pointerSelectedItem = true;
      clearPreparedDrag();
      ++previewRequest;
      ++systemPreviewRequest;
      unawaited(desktop.closeQuickLook());
      setState(() {
        marqueeSelecting = true;
        selectedApplication = null;
        preview = null;
        previewText = null;
        previewError = null;
      });
    },
    onChanged: (paths) {
      setState(() {
        selectedPaths
          ..clear()
          ..addAll(paths);
        if (selected == null || !paths.contains(selected!.path)) {
          selected = selection.firstOrNull;
        }
        status = defaultStatus();
      });
    },
    onEnd: () {
      pointerSelectedItem = false;
      setState(() => marqueeSelecting = false);
      if (selected != null) {
        unawaited(select(selected!, preserveSelection: true));
      }
    },
    child: child,
  );

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

  Future<void> receiveFiles(
    List<String> paths,
    String destination, {
    bool reportFastSuccess = true,
  }) async {
    if (busy || paths.isEmpty) return;
    final doc = document;
    if (doc == null) {
      if (paths.every(isReadableArchivePath)) {
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
          if (HarmonyBridge.supported) {
            await HarmonyBridge.finishSave(target.path);
          }
          message('压缩包已创建');
        },
        title: '正在创建压缩包',
        archivePath: target.path,
        reportFastSuccess: reportFastSuccess,
      );
      await loadArchive(target.path, encoding: settings.archive.createEncoding);
      return;
    }
    await run(
      () async {
        final result = await service.importFiles(doc, paths, destination);
        refreshDocument(result);
        message('已导入 ${paths.length} 个项目');
      },
      title: '正在导入文件',
      reportFastSuccess: reportFastSuccess,
    );
  }

  Future<void> verifyArchive() async {
    final doc = document;
    if (doc == null || busy) return;
    await run(() async {
      final result = await service.verify(doc);
      message('校验通过：${result['files']} 个项目，${result['bytes']} 字节');
    }, title: '正在测试压缩包');
  }

  bool inlineRenaming(ArchiveEntry entry) =>
      !renameDialogOpen && renamingEntry?.path == entry.path;

  void cancelRename({bool focus = true}) {
    if (!mounted || renamingEntry == null) return;
    setState(() {
      renamingEntry = null;
      renamingDocument = null;
    });
    if (focus) fileFocus.requestFocus();
  }

  Future<void> renameSelection() async {
    final doc = document, entry = selected;
    if (doc == null ||
        entry == null ||
        busy ||
        closing ||
        !doc.writable ||
        selectedPaths.length != 1 ||
        renamingEntry != null) {
      return;
    }
    clearPreparedDrag();
    final compact = MediaQuery.sizeOf(context).width < 800;
    setState(() {
      renamingEntry = entry;
      renamingDocument = doc;
      renameDialogOpen = compact;
    });
    if (!compact) return;
    try {
      await showAuxiliaryDialog<bool>(
        context: context,
        settings: settings,
        kind: 'rename',
        data: {'name': entry.name, 'directory': entry.directory},
        decodeResult: (data) => data['value'] as bool?,
        onAction: (_, data) async {
          await saveRename(doc, entry, data['name'] as String);
          return {};
        },
        barrierDismissible: false,
        builder: (dialogContext) => ArchiveNameEditor(
          name: entry.name,
          directory: entry.directory,
          compact: true,
          onRename: (name) async {
            await saveRename(doc, entry, name);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      );
    } finally {
      if (mounted) {
        cancelRename();
        setState(() => renameDialogOpen = false);
        fileFocus.requestFocus();
      }
    }
  }

  Future<void> saveRename(
    ArchiveDocument doc,
    ArchiveEntry entry,
    String name,
  ) async {
    Object? failure;
    var completed = false;
    await run(
      () async {
        try {
          if (document?.path != doc.path) throw StateError('操作已取消');
          final updated = await service.renameEntry(doc, entry, name);
          if (!mounted) return;
          final parent = p.posix.dirname(entry.normalized);
          final target = parent == '.' ? name : '$parent/$name';
          final selectedPath = selected?.path == entry.path
              ? target
              : selected?.normalized;
          cancelRename(focus: false);
          refreshDocument(updated);
          navigate(parent == '.' ? '' : parent);
          final nextSelection = selectedPath == null
              ? null
              : updated.index.byNormalized[selectedPath];
          if (nextSelection != null) await select(nextSelection);
          completed = true;
          message('重命名完成');
        } catch (error) {
          failure = error;
          rethrow;
        }
      },
      title: '正在重命名',
      archivePath: doc.path,
    );
    if (failure != null) throw failure!;
    if (!completed) throw StateError('操作已取消');
    if (mounted && !renameDialogOpen) fileFocus.requestFocus();
  }

  Widget entryName(
    ArchiveEntry entry, {
    double fontSize = 12,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
    String? columnParent,
  }) {
    if (inlineRenaming(entry)) {
      final doc = renamingDocument!;
      return ArchiveNameEditor(
        key: ValueKey('rename-${entry.path}'),
        name: entry.name,
        directory: entry.directory,
        fontSize: fontSize,
        textAlign: textAlign,
        onRename: (name) => saveRename(doc, entry, name),
        onCancel: cancelRename,
        onDismiss: () => cancelRename(focus: false),
      );
    }
    return Text(
      entry.name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.3,
        color: entryForeground(entry, columnParent: columnParent),
      ),
    );
  }

  void openCommand() {
    if (busy || renamingEntry != null) return;
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        fileFocus.hasPrimaryFocus &&
        selection.isNotEmpty) {
      openSelection();
    } else {
      pickArchive();
    }
  }

  Future<String?> entryNameDialog(bool directory) async {
    if (!mounted) return null;
    final input = TextEditingController(
      text: translateAppText(
        directory ? '未命名文件夹' : '未命名.txt',
        settings.locale.languageCode,
      ),
    );
    if (settings.separateWindows || MediaQuery.sizeOf(context).width < 800) {
      final name = input.text;
      input.dispose();
      return showAuxiliaryDialog<String>(
        context: context,
        settings: settings,
        kind: 'entryName',
        data: {'title': directory ? '新建文件夹' : '新建空白文档', 'name': name},
        decodeResult: (data) => data['value'] as String?,
        builder: (_) => EntryNameDialog(
          title: directory ? '新建文件夹' : '新建空白文档',
          initialName: name,
        ),
      );
    }
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
    if (busy || (document != null && !document!.writable)) {
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
        reportFastSuccess: false,
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
        await receiveFiles(paths, destination, reportFastSuccess: false);
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
    return (!widget.enableNativeTransfers || HarmonyBridge.supported)
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
    await run(
      () async {
        final updated = await service.transferEntries(
          doc,
          entries,
          destination,
          move: true,
        );
        refreshDocument(updated);
        message('已移动 ${entries.length} 个项目');
      },
      title: '正在移动文件',
      reportFastSuccess: false,
    );
  }

  void clearPreparedDrag() {
    armedDrag = null;
    if (widget.enableNativeTransfers && desktop.supportsQuickLook) {
      unawaited(
        desktop.prepareFileDrag([], movable: false, frame: [0, 0, 0, 0]),
      );
    }
  }

  bool dragResultNeedsFeedback() {
    final startedAt = activeDragStartedAt;
    activeDragStartedAt = null;
    return startedAt != null &&
        DateTime.now().difference(startedAt) >=
            const Duration(milliseconds: 500);
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
          activeDragStartedAt = DateTime.now();
          await desktop.startFileDrag(paths, movable: doc.writable);
          if (mounted) setState(() => status = '拖拽 ${roots.length} 个项目');
        },
        success: '拖拽文件已准备好',
        current: () => document == doc,
        reportFastSuccess: false,
      );
    } catch (e) {
      activeDrag = null;
      activeDragStartedAt = null;
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
    if (inlineRenaming(entry)) return child;
    if (!widget.enableNativeTransfers || HarmonyBridge.supported) {
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
            reportFastSuccess: false,
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
          final startedAt = DateTime.now();
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
                showFeedback:
                    result == DropOperation.forbidden ||
                    result == DropOperation.none ||
                    result == DropOperation.userCancelled ||
                    DateTime.now().difference(startedAt) >=
                        const Duration(milliseconds: 500),
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
        marqueeSelecting ||
        searchFocus.hasFocus ||
        busy ||
        document == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (renamingEntry != null) return KeyEventResult.ignored;
    if ((!mac &&
            event.logicalKey == LogicalKeyboardKey.f2 &&
            !keys.isMetaPressed &&
            !keys.isControlPressed &&
            !keys.isAltPressed) ||
        (mac &&
            enter &&
            !keys.isMetaPressed &&
            !keys.isControlPressed &&
            !keys.isAltPressed &&
            !keys.isShiftPressed)) {
      renameSelection();
      return KeyEventResult.handled;
    }
    if ((mac ? keys.isMetaPressed : keys.isControlPressed) &&
        !keys.isShiftPressed &&
        !keys.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        handleMenuCommand('openSelection');
        return KeyEventResult.handled;
      }
      if (mac && event.logicalKey == LogicalKeyboardKey.keyO) {
        openCommand();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        handleMenuCommand('enclosingFolder');
        return KeyEventResult.handled;
      }
    }
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
    if (!mac &&
        enter &&
        selected != null &&
        !keys.isMetaPressed &&
        !keys.isControlPressed &&
        !keys.isAltPressed) {
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
    final app = entry.directory || isReadableArchivePath(entry.name)
        ? null
        : await desktop.defaultApplication(entry.name);
    if (mounted && token == previewRequest) {
      setState(() => selectedApplication = app);
    }
    if (!entry.canExtract || !desktop.supportsFileIntegration) return;
    try {
      final apps = await desktop.applicationsForFile(entry.name);
      if (mounted && token == previewRequest) {
        setState(() {
          applicationMenuName = entry.name;
          menuApplications = apps;
        });
      }
    } catch (_) {
      // The application chooser remains available if discovery fails.
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
        reportFastSuccess: false,
        reportSuccess: false,
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
    child: Builder(
      builder: (context) => propertyWindowData == null
          ? workspaceBody(context)
          : Scaffold(
              key: const ValueKey('properties-window-page'),
              backgroundColor: context.theme.colors.card,
              body: Column(
                children: [
                  if (propertyActionError != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: AppText(
                        propertyActionError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: inspectorPanel(
                      summaryLayout: true,
                      inProperties: true,
                    ),
                  ),
                ],
              ),
            ),
    ),
  );

  Widget workspaceBody(BuildContext context) => CallbackShortcuts(
    bindings: {
      ...menuShortcutBindings,
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): openSettings,
      const SingleActivator(LogicalKeyboardKey.comma, control: true):
          openSettings,
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
              textEditing: menuTextEditing,
              menus: applicationMenus,
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
            listenable: Listenable.merge([feedback, auxiliaryModalDepth]),
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
                          if (desktopLayout &&
                              compactSearchOpen &&
                              document != null)
                            desktopSearchBar(),
                          Expanded(
                            child: Scaffold(
                              key: contentScaffold,
                              drawer: desktopLayout
                                  ? null
                                  : Drawer(width: 240, child: sidebar()),
                              body: splitterRow(
                                resizerKey: 'sidebar-resizer',
                                enabled: desktopLayout,
                                boundaryWidth: leftWidth,
                                resize: (dx) =>
                                    sidebarWidth = (leftWidth + dx).clamp(
                                      160.0,
                                      (constraints.maxWidth * .28).clamp(
                                        160.0,
                                        double.infinity,
                                      ),
                                    ),
                                children: [
                                  if (desktopLayout)
                                    SizedBox(
                                      width: leftWidth,
                                      child: sidebar(),
                                    ),
                                  if (desktopLayout)
                                    splitterLine('sidebar-resizer'),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        if (tabs.length > 1) archiveTabs(),
                                        Expanded(
                                          child: splitterRow(
                                            resizerKey: 'inspector-resizer',
                                            enabled: inspectorVisible,
                                            boundaryWidth: rightWidth,
                                            trailing: true,
                                            resize: (dx) => inspectorWidth =
                                                (rightWidth - dx).clamp(
                                                  220.0,
                                                  (constraints.maxWidth * .32)
                                                      .clamp(
                                                        220.0,
                                                        double.infinity,
                                                      ),
                                                ),
                                            children: [
                                              Expanded(
                                                child: directoryBackground(
                                                  child: document == null
                                                      ? dropTarget(
                                                          '',
                                                          emptyWorkspace(),
                                                        )
                                                      : FileContextMenu(
                                                          onProperties: busy
                                                              ? null
                                                              : () {
                                                                  clearSelection();
                                                                  showProperties();
                                                                },
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
                                                          onExtractAll: busy
                                                              ? null
                                                              : () => extract(),
                                                          onExtractAllNamed:
                                                              busy
                                                              ? null
                                                              : () => extract(
                                                                  namedFolder:
                                                                      true,
                                                                ),
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
                                                splitterLine(
                                                  'inspector-resizer',
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
                          footer(desktopLayout),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: workspaceFeedback(desktopLayout),
                  ),
                ),
                if (auxiliaryModalDepth.value > 0)
                  Positioned.fill(
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (_, _) => KeyEventResult.handled,
                      child: const AbsorbPointer(child: SizedBox.expand()),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Map<ShortcutActivator, VoidCallback> get menuShortcutBindings {
    const keys = {
      'n': LogicalKeyboardKey.keyN,
      'o': LogicalKeyboardKey.keyO,
      'e': LogicalKeyboardKey.keyE,
      'i': LogicalKeyboardKey.keyI,
      'f': LogicalKeyboardKey.keyF,
      '1': LogicalKeyboardKey.digit1,
      '2': LogicalKeyboardKey.digit2,
      '3': LogicalKeyboardKey.digit3,
      '4': LogicalKeyboardKey.digit4,
      '[': LogicalKeyboardKey.bracketLeft,
      ']': LogicalKeyboardKey.bracketRight,
      '=': LogicalKeyboardKey.equal,
      '-': LogicalKeyboardKey.minus,
      '↑': LogicalKeyboardKey.arrowUp,
      '↓': LogicalKeyboardKey.arrowDown,
    };
    final bindings = <ShortcutActivator, VoidCallback>{};
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    void collect(List<ApplicationMenuItem> items) {
      for (final item in items) {
        if (item.children != null) collect(item.children!);
        final key = keys[item.key];
        if (key == null || item.command == null) continue;
        bindings[SingleActivator(
          key,
          meta: mac && item.modifiers.contains('command'),
          control: !mac && item.modifiers.contains('command'),
          shift: item.modifiers.contains('shift'),
        )] = () =>
            handleMenuCommand(item.command!);
      }
    }

    collect(applicationMenus);
    return bindings;
  }

  Widget splitterLine(String key) => Container(
    key: ValueKey('$key-line'),
    width: 1,
    color: context.theme.colors.border,
  );

  Widget splitterRow({
    required String resizerKey,
    required bool enabled,
    required double boundaryWidth,
    required void Function(double) resize,
    required List<Widget> children,
    bool trailing = false,
  }) => Stack(
    fit: StackFit.expand,
    children: [
      Row(children: children),
      if (enabled)
        Positioned(
          left: trailing ? null : boundaryWidth - 6,
          right: trailing ? boundaryWidth - 6 : null,
          top: 0,
          bottom: 0,
          width: 13,
          child: splitter(resizerKey, resize),
        ),
    ],
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
      child: const SizedBox.expand(),
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
                        right: BorderSide(color: context.theme.colors.border),
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
                          color: context.theme.colors.muted,
                          child: AppText(
                            parent.isEmpty
                                ? p.basename(document!.path)
                                : p.posix.basename(parent),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                        Expanded(
                          child: FileContextMenu(
                            onExtractAll: busy ? null : () => extract(),
                            onExtractAllNamed: busy
                                ? null
                                : () => extract(namedFolder: true),
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
          style: TextStyle(fontSize: 12, color: muted),
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
    return fileSelectionArea(
      ListView.builder(
        controller: controller,
        cacheExtent: 0,
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
                joinPrevious:
                    i > 0 && selectedPaths.contains(items[i - 1].path),
                joinNext:
                    i + 1 < items.length &&
                    selectedPaths.contains(items[i + 1].path),
                iconSize: rowIconSize,
                horizontalPadding: rowPadding,
                height: rowHeight,
              ),
      ),
      controller,
      parent: parent,
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
    triggerBuilder: (_, shown, toggle) => DesktopButton(
      key: const ValueKey('selection-open-menu'),
      flat: true,
      tooltip: '打开方式',
      minHeight: 28,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      onPressed: busy ? null : toggle,
      child: Icon(
        shown ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_up,
        size: 12,
      ),
    ),
    applications: desktop.supportsFileIntegration
        ? () => desktop.applicationsForFile(entry.name)
        : null,
    onOpenInHiZip:
        !busy && entry.canExtract && isReadableArchivePath(entry.name)
        ? () => openEntry(entry)
        : null,
    onOpenWith: busy || !desktop.supportsFileIntegration
        ? null
        : (app) => openEntry(entry, application: app),
    onChooseApplication: busy || !desktop.supportsApplicationSelection
        ? null
        : () => chooseOpenApplication(entry),
    child: const SizedBox(width: 28, height: 28),
  );

  Widget contextMenu(
    ArchiveEntry entry,
    Widget child, {
    String? columnParent,
  }) => FileContextMenu(
    enabled: !inlineRenaming(entry),
    onProperties: busy ? null : showProperties,
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
    onOpenInHiZip:
        !busy &&
            !entry.directory &&
            entry.canExtract &&
            isReadableArchivePath(entry.name)
        ? () => openEntry(entry)
        : null,
    onPreview: desktop.supportsQuickLook && !busy && entry.canExtract
        ? quickLook
        : null,
    onCopy: busy || !entry.safe ? null : copyFiles,
    onPaste: busy || !document!.writable
        ? null
        : () => pasteInto(entry.directory ? entry.normalized : folder),
    onExtract: busy || !entry.safe ? null : () => extract(onlySelected: true),
    onDelete: busy || !document!.writable ? null : deleteSelection,
    onRename: busy || !document!.writable || selectedPaths.length > 1
        ? null
        : renameSelection,
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
    onChooseApplication: busy || !desktop.supportsApplicationSelection
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
        onProperties: busy
            ? null
            : () {
                clearSelection();
                navigate('');
                showProperties();
              },
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

  Future<void> showProperties({bool archiveOverview = false}) async {
    final doc = document;
    if (doc == null) return;
    final targetFolder = archiveOverview ? '' : folder;
    final targetSelection = archiveOverview
        ? <ArchiveEntry>[]
        : List<ArchiveEntry>.of(selection);
    final key = jsonEncode([
      doc.path,
      targetFolder,
      targetSelection.map((entry) => entry.path).toList(),
    ]);
    final transport = propertiesWindows.putIfAbsent(
      key,
      () =>
          widget.propertiesWindowFactory?.call() ??
          PropertiesWindowTransport(settings: settings),
    );
    Map<String, dynamic> snapshot() => archivePropertiesSnapshot(
      tabFor(doc.path)?.document ?? doc,
      targetFolder,
      targetSelection,
    );
    try {
      Future<Map<String, dynamic>> action(
        String action,
        Map<String, dynamic> data,
      ) async {
        if (!mounted || tabFor(doc.path) == null) throw StateError('操作已取消');
        if (action == 'saveComment') {
          final updated = await service.writeComment(
            tabFor(doc.path)!.document,
            data['text'] as String,
            original: data['original'] as String,
          );
          if (!mounted) throw StateError('操作已取消');
          setState(() {
            tabFor(doc.path)!.document = updated;
            if (document?.path == doc.path) document = updated;
          });
          message('注释已保存');
        } else {
          activateTab(tabFor(doc.path));
          navigate(targetFolder);
          setState(() {
            selectedPaths
              ..clear()
              ..addAll(targetSelection.map((entry) => entry.path));
            selected = targetSelection.firstOrNull;
          });
          if (action == 'open') await openSelection();
          if (action == 'extract') {
            await extract(
              onlySelected: targetSelection.isNotEmpty,
              currentFolder: targetSelection.isEmpty && targetFolder.isNotEmpty,
            );
          }
          if (action == 'extractNamed') await extract(namedFolder: true);
        }
        return transport.payload(snapshot());
      }

      Future<void> showInline() async {
        await transport.hide();
        if (!mounted) return;
        await showAppDialog<void>(
          context: context,
          languageCode: settings.locale.languageCode,
          barrierDismissible: false,
          builder: (_) => InlinePropertiesDialog(
            settings: settings,
            data: snapshot(),
            onAction: action,
          ),
        );
        if (mounted) fileFocus.requestFocus();
      }

      if (!settings.separateWindows || MediaQuery.sizeOf(context).width < 800) {
        await showInline();
        return;
      }
      final shown = await transport.show(snapshot(), action);
      if (!shown && mounted) {
        if (!settings.separateWindows) {
          await showInline();
        } else {
          message('属性窗口未能启动，请重试。', error: true);
        }
      }
    } catch (error) {
      if (mounted) message(error.toString(), error: true);
    }
  }

  void applyPropertiesData(Map<String, dynamic> data) {
    propertyWindowData = data;
    document = archivePropertiesDocument(data);
    folder = data['folder'] as String;
    selectedPaths
      ..clear()
      ..addAll(archivePropertiesSelection(data).map((entry) => entry.path));
    selected = archivePropertiesSelection(data).firstOrNull;
    gallery = true;
  }

  Future<bool> savePropertyDrafts() async {
    for (final draft in commentDrafts.values) {
      await draft.save();
      if (draft.editing) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant ArchiveWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.propertiesData != null &&
        !identical(oldWidget.propertiesData, widget.propertiesData)) {
      applyPropertiesData(widget.propertiesData!);
    }
  }

  Future<void> propertyAction(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (busy) return;
    setState(() {
      busy = true;
      propertyActionError = null;
    });
    try {
      final updated = await widget.propertiesAction!(action, data);
      if (mounted) setState(() => applyPropertiesData(updated));
    } catch (error) {
      if (mounted) setState(() => propertyActionError = error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
      decoration: BoxDecoration(color: context.theme.colors.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: AppText('目录', style: TextStyle(fontSize: 11, color: muted)),
          ),
          Expanded(
            child: document == null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: AppText(
                      '未打开压缩包',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    cacheExtent: 0,
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
                                      ? context.theme.colors.border
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
                                                color: context
                                                    .theme
                                                    .colors
                                                    .mutedForeground,
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
        color: context.theme.colors.muted,
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
                      ? context.theme.colors.card
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

  List<ApplicationMenuItem> get applicationMenus {
    final available =
        !busy &&
        auxiliaryModalDepth.value == 0 &&
        !closing &&
        renamingEntry == null &&
        !prompting &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final hasDocument = available && document != null;
    final writable = hasDocument && document!.writable;
    final entries = selection;
    final hasSelection = hasDocument && entries.isNotEmpty;
    final roots = topLevelEntries(entries);
    final canTransfer =
        writable &&
        hasSelection &&
        entries.every(
          (entry) => entry.directory ? entry.safe : entry.canExtract,
        ) &&
        (acceptsSelectionDestination('', roots) ||
            document!.index.byNormalized.values
                .where((entry) => entry.directory)
                .any(
                  (entry) =>
                      acceptsSelectionDestination(entry.normalized, roots),
                ));
    final one = hasSelection && entries.length == 1 ? entries.single : null;
    final canOpen =
        hasSelection &&
        entries.any((entry) => entry.directory || entry.canExtract);
    final canOpenWith =
        one?.canExtract == true && desktop.supportsFileIntegration;
    final textEditing = menuTextEditing;
    const divider = ApplicationMenuItem.separator();
    ApplicationMenuItem action(
      String title,
      String command,
      bool enabled, {
      bool checked = false,
      String key = '',
      List<String> modifiers = const ['command'],
    }) => ApplicationMenuItem(
      title,
      command: command,
      enabled: enabled,
      checked: checked,
      key: key,
      modifiers: modifiers,
    );
    ApplicationMenuItem submenu(
      String title,
      List<ApplicationMenuItem> children,
    ) => ApplicationMenuItem(title, children: children);
    return [
      submenu('文件', [
        action(
          '打开…',
          'open',
          available && (!hasSelection || canOpen || textEditing),
          key: 'o',
        ),
        action(
          '打开压缩包…',
          'openArchive',
          available,
          key: 'o',
          modifiers: const ['command', 'shift'],
        ),
        submenu('最近打开', [
          if (recent.isEmpty)
            const ApplicationMenuItem('暂无最近打开的文件', enabled: false),
          for (final path in recent.take(10))
            action(p.basename(path), 'recent:$path', available),
          divider,
          action('清除菜单', 'clearRecent', recent.isNotEmpty),
        ]),
        if (HarmonyBridge.supported) action('保存副本…', 'saveCopy', hasDocument),
        divider,
        action(
          '快速创建 ZIP',
          'quickZip',
          available && (availableCreateFormats?.contains('zip') ?? true),
        ),
        action(
          '创建压缩包…',
          'create',
          available && createFormats.isNotEmpty,
          key: 'n',
        ),
        action(
          '新建文件夹…',
          'newFolder',
          writable,
          key: 'n',
          modifiers: const ['command', 'shift'],
        ),
        action('新建空白文档…', 'newDocument', writable),
        action('添加文件…', 'addFiles', writable),
        action('添加文件夹…', 'addFolder', writable),
        divider,
        action('打开所选项目', 'openSelection', canOpen, key: '↓'),
        ApplicationMenuItem(
          '打开方式',
          enabled:
              canOpenWith ||
              (one?.canExtract == true && isReadableArchivePath(one!.name)),
          children: [
            if (one != null && isReadableArchivePath(one.name))
              action('在 HiZip 中打开', 'openInHiZip', one.canExtract),
            if (canOpenWith) ...[
              for (final app
                  in applicationMenuName == one!.name
                      ? menuApplications
                      : <FileApplication>[])
                action(
                  '${app.name}${app.isDefault ? '（默认）' : ''}',
                  'openWith:${app.path}',
                  true,
                ),
              if (desktop.supportsApplicationSelection) ...[
                divider,
                action('其他…', 'chooseApplication', true),
              ],
            ],
          ],
        ),
        if (desktop.supportsQuickLook)
          action(
            '快速查看',
            'quickLook',
            one?.canExtract == true && !textEditing,
            key: ' ',
            modifiers: const [],
          ),
        divider,
        action(
          '解压所选…',
          'extractSelection',
          hasSelection && entries.every((entry) => entry.safe),
        ),
        action('解压当前文件夹…', 'extractFolder', hasDocument && folder.isNotEmpty),
        action('解压全部…', 'extract', hasDocument, key: 'e'),
        action('解压全部到同名文件夹…', 'extractNamed', hasDocument),
        action('校验压缩包', 'verify', hasDocument),
        divider,
        action('属性', 'properties', hasDocument, key: 'i'),
        action('压缩包属性', 'archiveProperties', hasDocument),
        divider,
        action('关闭标签页', 'closeArchive', hasDocument, key: 'w'),
      ]),
      submenu('编辑', [
        action('撤销', 'undo', textEditing, key: 'z'),
        action(
          '重做',
          'redo',
          textEditing,
          key: 'z',
          modifiers: const ['command', 'shift'],
        ),
        divider,
        action('剪切', 'cut', textEditing, key: 'x'),
        action(
          '复制',
          'copy',
          textEditing || (hasSelection && entries.every((entry) => entry.safe)),
          key: 'c',
        ),
        action('粘贴', 'paste', textEditing || writable, key: 'v'),
        action('全选', 'selectAll', textEditing || hasDocument, key: 'a'),
        divider,
        action('移动到…', 'moveTo', canTransfer),
        action('复制到…', 'copyTo', canTransfer),
        action('重命名…', 'rename', writable && one != null),
        action('删除…', 'delete', writable && hasSelection, key: '\u{8}'),
        divider,
        action('搜索', 'search', hasDocument, key: 'f'),
      ]),
      submenu('显示', [
        action('图标视图', 'grid', hasDocument, checked: grid, key: '1'),
        action(
          '列表视图',
          'list',
          hasDocument,
          checked: !grid && !columns && !gallery,
          key: '2',
        ),
        action('多栏视图', 'columns', hasDocument, checked: columns, key: '3'),
        action('画廊视图', 'gallery', hasDocument, checked: gallery, key: '4'),
        divider,
        action('预览栏', 'inspector', hasDocument, checked: inspector),
        action('任务列表', 'tasks', !closing, checked: queueExpanded),
        submenu('排序方式', [
          for (final (column, title) in [
            ('name', '名称'),
            ('size', '大小'),
            ('modified', '修改日期'),
            ('kind', '种类'),
          ])
            action(
              title,
              'sort:$column',
              hasDocument,
              checked: listSortColumn == column,
            ),
          divider,
          action('升序', 'ascending', hasDocument, checked: listSortAscending),
          action('降序', 'descending', hasDocument, checked: !listSortAscending),
        ]),
        action(
          '放大图标',
          'largerIcons',
          hasDocument &&
              iconSize < BrowsingPreferences.maxIconSize(browsingView),
          key: '=',
        ),
        action(
          '缩小图标',
          'smallerIcons',
          hasDocument &&
              iconSize > BrowsingPreferences.minIconSize(browsingView),
          key: '-',
        ),
        divider,
        submenu('编码', [
          for (final encoding in archiveEncodings.entries)
            action(
              encoding.value,
              'encoding:${encoding.key}',
              hasDocument,
              checked: document?.encoding == encoding.key,
            ),
        ]),
      ]),
      submenu('前往', [
        action('返回', 'back', hasDocument && history.isNotEmpty, key: '['),
        action(
          '上级文件夹',
          'enclosingFolder',
          hasDocument && folder.isNotEmpty && !textEditing,
          key: '↑',
        ),
        action('压缩包根目录', 'archiveRoot', hasDocument && folder.isNotEmpty),
        divider,
        action(
          '上一个标签页',
          'previousTab',
          available && tabs.length > 1,
          key: '[',
          modifiers: const ['command', 'shift'],
        ),
        action(
          '下一个标签页',
          'nextTab',
          available && tabs.length > 1,
          key: ']',
          modifiers: const ['command', 'shift'],
        ),
      ]),
    ];
  }

  Widget applicationMenu() {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    DesktopMenuAction adapt(ApplicationMenuItem item) {
      if (item.separator) return const DesktopMenuAction.separator();
      final shortcut = item.key.isEmpty
          ? null
          : '${item.modifiers.contains('command') ? (mac ? '⌘' : 'Ctrl+') : ''}'
                '${item.modifiers.contains('shift') ? (mac ? '⇧' : 'Shift+') : ''}'
                '${item.key == ' ' ? appText(context, '空格') : item.key.toUpperCase()}';
      return DesktopMenuAction(
        item.title,
        item.enabled && item.command != null
            ? () => handleMenuCommand(item.command!)
            : null,
        children: item.children?.map(adapt).toList(),
        checked: item.checked,
        enabled: item.enabled,
        shortcut: shortcut,
      );
    }

    return FileContextMenu(
      key: const ValueKey('application-menu'),
      primaryClick: true,
      triggerBuilder: (_, shown, toggle) => Semantics(
        expanded: shown,
        child: DesktopIconButton(
          tooltip: '应用菜单',
          icon: const Icon(Icons.menu, size: 19),
          active: shown,
          onPressed: toggle,
        ),
      ),
      actions: [
        ...applicationMenus.map(adapt),
        const DesktopMenuAction.separator(),
        DesktopMenuAction('设置…', openSettings),
      ],
      child: const SizedBox(width: 30, height: 28),
    );
  }

  Widget toolbar(bool desktopLayout) => LayoutBuilder(
    builder: (context, constraints) {
      return Container(
        key: const ValueKey('workspace-top-bar'),
        height: !desktopLayout && compactSearchOpen
            ? windowChromeHeight().clamp(
                desktopInputHeight(context) + 12,
                double.infinity,
              )
            : windowChromeHeight(),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: context.theme.colors.muted,
          border: Border(
            bottom: BorderSide(color: context.theme.colors.border),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: windowDragArea(const SizedBox.expand())),
            Row(
              children: [
                windowLeadingControls(),
                if (!desktop.supportsMenuBar) applicationMenu(),
                Expanded(
                  child: !desktopLayout && compactSearchOpen && document != null
                      ? CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                closeCompactSearch,
                          },
                          child: Row(
                            children: [
                              Expanded(child: searchField()),
                              const SizedBox(width: 8),
                              tool(
                                '关闭搜索',
                                CupertinoIcons.xmark,
                                closeCompactSearch,
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
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
                              viewModeSelector(),
                              const SizedBox(width: 8),
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
                              tool(
                                '搜索',
                                FIcons.search,
                                openSearch,
                                active:
                                    compactSearchOpen || search.text.isNotEmpty,
                              ),
                              const SizedBox(width: 8),
                            ],
                            windowTrailingControls(),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget desktopSearchBar() => Container(
    key: const ValueKey('workspace-search-bar'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: context.theme.colors.muted,
      border: Border(bottom: BorderSide(color: context.theme.colors.border)),
    ),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): closeCompactSearch,
      },
      child: Row(
        children: [
          Expanded(child: searchField()),
          const SizedBox(width: 8),
          tool('关闭搜索', CupertinoIcons.xmark, closeCompactSearch),
        ],
      ),
    ),
  );

  Widget viewModeSelector() {
    Widget button(String title, IconData icon, String view) =>
        DesktopIconButton(
          tooltip: title,
          onPressed: () => changeView(view),
          active: browsingView == view,
          icon: Icon(icon, size: 17),
        );
    return Row(
      key: const ValueKey('view-mode-selector'),
      mainAxisSize: MainAxisSize.min,
      children: [
        button('图标视图', CupertinoIcons.square_grid_2x2, 'grid'),
        button('列表视图', CupertinoIcons.list_bullet, 'list'),
        button('多栏视图', CupertinoIcons.rectangle_split_3x1, 'columns'),
        button('画廊视图', CupertinoIcons.rectangle_stack, 'gallery'),
      ],
    );
  }

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
          bottom:
              20 +
              (document != null && !inspectorVisible
                  ? _selectionStripHeight
                  : 0),
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Align(
                alignment: Alignment.bottomRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Hi',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(
                                  alpha:
                                      Theme.of(context).brightness ==
                                          Brightness.light
                                      ? .8
                                      : .5,
                                ),
                          ),
                        ),
                        const TextSpan(text: 'Zip'),
                      ],
                    ),
                    key: const ValueKey('workspace-watermark'),
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: (constraints.maxWidth * .25).clamp(48.0, 144.0),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -4,
                      height: 1,
                      color: desktopColor(context, 0xffb0b0b0, 0x0dffffff),
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
        AppText('未打开压缩包', style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 14),
        DesktopButton(
          onPressed: busy ? null : pickArchive,
          child: const AppText('打开压缩包'),
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
                Icon(CupertinoIcons.chevron_right, size: 9, color: muted),
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
    height: desktopInputHeight(context),
    child: DesktopTextField(
      controller: search,
      focusNode: searchFocus,
      onTapOutside: (_) => closeCompactSearch(),
      hint: translateAppText('搜索', settings.locale.languageCode),
      prefix: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          FIcons.search,
          size: 13,
          color: context.theme.colors.mutedForeground,
        ),
      ),
      suffix: search.text.isEmpty
          ? null
          : ExcludeFocus(
              child: DesktopIconButton(
                key: const ValueKey('clear-archive-search'),
                tooltip: '清除搜索',
                onPressed: () {
                  search.clear();
                  searchFocus.requestFocus();
                },
                icon: const Icon(FIcons.x, size: 13),
              ),
            ),
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
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                : gallery
                ? galleryBrowser(items)
                : LayoutBuilder(
                    builder: (context, constraints) {
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
                          (cellWidth - 32).clamp(1.0, double.infinity),
                        );
                        final smallIcon = displaySize < 36;
                        final nameHeight = gridTextHeight(
                          context,
                          'Ag汉字あ한\nAg汉字あ한',
                          smallIcon ? 10 : 11,
                        );
                        final tileHeight =
                            displaySize +
                            (smallIcon ? 24 : 40) +
                            nameHeight.clamp(
                              desktopInputHeight(
                                context,
                                fontSize: smallIcon ? 10 : 11,
                              ),
                              double.infinity,
                            );
                        gridTileExtent = tileHeight;
                        gridPadding = margin;
                        gridSpacing = spacing;
                        return fileSelectionArea(
                          GridView.builder(
                            controller: listScroll,
                            cacheExtent: 0,
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
                                items.length +
                                (items.remainingCount > 0 ? 1 : 0),
                            itemBuilder: (_, i) => i == items.length
                                ? remainingItems(folder, items)
                                : tile(items[i], displaySize: displaySize),
                          ),
                          listScroll,
                        );
                      }
                      final availableWidth =
                          (constraints.maxWidth - 2 * (rowPadding + listInset))
                              .clamp(0.0, double.infinity);
                      final layout = ListColumnLayout(
                        availableWidth: availableWidth,
                        size: listSizeWidth,
                        modified: listModifiedWidth,
                        kind: listKindWidth,
                      );
                      final compact = !layout.showMetadata;
                      final nameWidth = layout.name;
                      final kindWidth = layout.kind;
                      final contentWidth = availableWidth;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 27,
                            color: context.theme.colors.muted,
                            padding: EdgeInsets.symmetric(
                              horizontal: rowPadding + listInset,
                            ),
                            child: SizedBox(
                              width: contentWidth,
                              child: Row(
                                children: [
                                  listHeaderCell(
                                    '名称',
                                    'name',
                                    nameWidth,
                                    layout: layout,
                                  ),
                                  if (!compact) ...[
                                    listHeaderCell(
                                      '大小',
                                      'size',
                                      listSizeWidth,
                                      layout: layout,
                                    ),
                                    listHeaderCell(
                                      '修改日期',
                                      'modified',
                                      listModifiedWidth,
                                      layout: layout,
                                    ),
                                    listHeaderCell(
                                      '种类',
                                      'kind',
                                      kindWidth,
                                      layout: layout,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: fileSelectionArea(
                              ListView.builder(
                                controller: listScroll,
                                cacheExtent: 0,
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
                                        kindWidth: compact ? null : kindWidth,
                                      ),
                              ),
                              listScroll,
                            ),
                          ),
                        ],
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
              color: selectedPaths.contains(e.path)
                  ? entryForeground(e)
                  : e.directory
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

  Widget listHeaderCell(
    String label,
    String column,
    double width, {
    required ListColumnLayout layout,
  }) {
    final active = listSortColumn == column;
    final resizable = layout.showMetadata && column != 'kind';
    return SizedBox(
      key: ValueKey('list-header-$column'),
      width: width,
      height: 27,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? null : () => sortList(column),
            child: Padding(
              padding: EdgeInsets.only(
                left: column == 'name' ? 0 : 8,
                right: 8,
              ),
              child: Row(
                mainAxisAlignment: column == 'name'
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: AppText(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
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
          if (resizable)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: busy
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  key: ValueKey('list-column-resizer-$column'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: busy
                      ? null
                      : (details) {
                          listColumnDragStart = details.globalPosition.dx;
                          listColumnDragLayout = layout;
                        },
                  onHorizontalDragUpdate: busy
                      ? null
                      : (details) => resizeListColumn(
                          column,
                          details.globalPosition.dx - listColumnDragStart,
                          layout: layout,
                        ),
                  onHorizontalDragEnd: busy
                      ? null
                      : (_) => finishListColumnResize(),
                  onHorizontalDragCancel: busy ? null : finishListColumnResize,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
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
      Expanded(child: entryName(e, columnParent: columnParent)),
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
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(
            CupertinoIcons.lock,
            size: 13,
            color: entryForeground(
              e,
              secondary: true,
              columnParent: columnParent,
            ),
          ),
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
          selectionPath: e.path,
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
          onSelect: busy || inlineRenaming(e)
              ? null
              : () {
                  if (columnParent != null) navigate(columnParent);
                  selectFromPointer(e);
                  if (columns) revealColumns();
                },
          onDragStart:
              !busy &&
                  !inlineRenaming(e) &&
                  widget.enableNativeTransfers &&
                  desktop.supportsQuickLook
              ? () => startMacDrag(e)
              : null,
          onActivate: busy || inlineRenaming(e) ? null : () => openEntry(e),
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
                    key: ValueKey('list-cell-${e.path}-name'),
                    width: nameWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: rowName(
                        e,
                        compact,
                        columnParent: columnParent,
                        iconSize: iconSize,
                      ),
                    ),
                  ),
                if (!compact) ...[
                  SizedBox(
                    key: ValueKey('list-cell-${e.path}-size'),
                    width: sizeWidth ?? 85,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: AppText(
                        e.directory ? '—' : formatSize(e.size),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  ),
                  SizedBox(
                    key: ValueKey('list-cell-${e.path}-modified'),
                    width: modifiedWidth ?? 115,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: AppText(
                        date(e.modified),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  ),
                  SizedBox(
                    key: ValueKey('list-cell-${e.path}-kind'),
                    width: kindWidth ?? 85,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: AppText(
                        kind(e),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
  Widget tile(ArchiveEntry e, {required double displaySize}) {
    return FileItemHitArea(
      key: ValueKey('grid-hit-area-${e.path}'),
      builder: (iconRegion, nameRegion) {
        final hitRegions = [iconRegion, nameRegion];
        return contextMenu(
          e,
          transferable(
            e,
            FileItemSurface(
              key: ValueKey('file-${e.path}'),
              selectionPath: e.path,
              name: e.name,
              paintSelection: false,
              hitRegions: hitRegions,
              selectionHighlight: settings.selectionHighlight,
              selected: selectedPaths.contains(e.path),
              onSelect: busy || inlineRenaming(e)
                  ? null
                  : () {
                      selectFromPointer(e);
                    },
              onDragStart:
                  !busy &&
                      !inlineRenaming(e) &&
                      widget.enableNativeTransfers &&
                      desktop.supportsQuickLook
                  ? () => startMacDrag(e)
                  : null,
              onActivate: busy || inlineRenaming(e) ? null : () => openEntry(e),
              child: Padding(
                padding: EdgeInsets.all(displaySize < 36 ? 4 : 8),
                child: Column(
                  children: [
                    DecoratedBox(
                      key: ValueKey('grid-icon-background-${e.path}'),
                      decoration: BoxDecoration(
                        color: selectedPaths.contains(e.path)
                            ? const Color(0x33808080)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        key: iconRegion,
                        padding: EdgeInsets.all(displaySize < 36 ? 4 : 8),
                        child: fileIcon(e, size: displaySize),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: DecoratedBox(
                          key: ValueKey('grid-name-background-${e.path}'),
                          decoration: BoxDecoration(
                            color: selectedPaths.contains(e.path)
                                ? fileSelectionBackground(
                                    context,
                                    settings.selectionHighlight,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Padding(
                            key: nameRegion,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: entryName(
                              e,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              fontSize: displaySize < 36 ? 10 : 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double gridTextHeight(BuildContext context, String sample, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: sample,
        style: DefaultTextStyle.of(
          context,
        ).style.merge(TextStyle(fontSize: fontSize, height: 1.3)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return height;
  }

  Widget galleryBrowser(DirectoryListing items) {
    final doc = document!;
    return GalleryBrowser(
      document: doc,
      enabled: !busy && !closing,
      revealSelection: !marqueeSelecting,
      selectionAreaBuilder: (controller, child) =>
          fileSelectionArea(child, controller),
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
      name: (entry) => entryName(entry, fontSize: 10),
      item: (entry, child) => contextMenu(
        entry,
        transferable(
          entry,
          FileItemSurface(
            key: ValueKey('file-${entry.path}'),
            selectionPath: entry.path,
            name: entry.name,
            selected: selectedPaths.contains(entry.path),
            selectionHighlight: settings.selectionHighlight,
            onSelect: busy || inlineRenaming(entry)
                ? null
                : () => selectFromPointer(entry),
            onActivate: busy || inlineRenaming(entry)
                ? null
                : () => openEntry(entry),
            onDragStart:
                !busy &&
                    !inlineRenaming(entry) &&
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
      password: doc.password,
      nativePath: doc.nativePath,
      comment: doc.comment,
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
    if (propertyWindowData != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in propertyWindowData!['actions'] as List)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DesktopButton(
                key: ValueKey('property-action-${action['id']}'),
                onPressed: busy
                    ? null
                    : () => propertyAction(action['id'] as String),
                child: AppText(action['label'] as String),
              ),
            ),
        ],
      );
    }
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
    final overview = entries.isEmpty;
    final archiveOverview = overview && folder.isEmpty;
    final extractButton = DesktopButton(
      key: const ValueKey('selection-extract'),
      onPressed: busy
          ? null
          : () => extract(
              onlySelected: !overview,
              currentFolder: overview && !archiveOverview,
            ),
      child: AppText(archiveOverview ? '解压全部' : '解压'),
    );
    final extractNamedButton = archiveOverview
        ? DesktopButton(
            key: const ValueKey('selection-extract-named'),
            onPressed: busy ? null : () => extract(namedFolder: true),
            child: const AppText('解压全部到同名文件夹'),
          )
        : null;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canOpen) ...[open, const SizedBox(width: 8)],
          extractButton,
          if (extractNamedButton != null) ...[
            const SizedBox(width: 8),
            extractNamedButton,
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canOpen) ...[open, const SizedBox(height: 8)],
        extractButton,
        if (extractNamedButton != null) ...[
          const SizedBox(height: 8),
          extractNamedButton,
        ],
      ],
    );
  }

  Widget selectionStrip() => Container(
    key: const ValueKey('selection-strip'),
    height: _selectionStripHeight,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: LayoutBuilder(
      builder: (context, bounds) => Row(
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
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bounds.maxWidth * .75),
            child: SingleChildScrollView(
              key: const ValueKey('selection-actions-scroll'),
              scrollDirection: Axis.horizontal,
              primary: false,
              child: selectionActions(compact: true),
            ),
          ),
        ],
      ),
    ),
  );

  Widget openButton({bool compact = false}) {
    final openInHiZip =
        selected != null && isReadableArchivePath(selected!.name);
    final split =
        selected != null && (desktop.supportsFileIntegration || openInHiZip);
    final label = openInHiZip
        ? '在 HiZip 中打开'
        : selectedApplication == null
        ? '在默认应用中打开'
        : '用 ${selectedApplication!.name} 打开';
    final icon = openInHiZip ? null : selectedApplication?.icon;
    final content = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (openInHiZip) ...[
          const Icon(Icons.archive_outlined, size: 18),
          const SizedBox(width: 6),
        ],
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
    final style = context.theme.buttonStyles
        .resolve({FButtonVariant.outline, context.platformVariant})
        .resolve({FButtonSizeVariant.sm, context.platformVariant});
    return Container(
      key: const ValueKey('selection-open-split'),
      height: 28,
      decoration: style.decoration.resolve({
        if (busy) FTappableVariant.disabled,
      }),
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
  Widget inspectorLayout({
    required Widget preview,
    required Widget information,
    required Widget actions,
    bool? summaryLayout,
  }) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            key: const ValueKey('inspector-scroll'),
            padding: embeddedProperties
                ? EdgeInsets.zero
                : const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (viewport.maxHeight - (embeddedProperties ? 0 : 32))
                    .clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: (summaryLayout ?? gallery)
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: (summaryLayout ?? gallery)
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
      ),
      DecoratedBox(
        key: const ValueKey('inspector-actions'),
        decoration: BoxDecoration(
          color: propertyWindowData != null
              ? context.theme.colors.card
              : context.theme.colors.muted,
          border: Border(top: BorderSide(color: context.theme.colors.border)),
        ),
        child: Padding(
          padding: embeddedProperties
              ? const EdgeInsets.only(top: 16)
              : const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: actions,
        ),
      ),
    ],
  );

  bool get embeddedProperties =>
      propertyWindowData != null &&
      context.findAncestorWidgetOfExactType<DesktopDialog>() != null;

  Widget inspectorPanel({bool? summaryLayout, bool inProperties = false}) {
    final summarized = summaryLayout ?? gallery;
    return Container(
      key: ValueKey(inProperties ? 'properties-panel' : 'inspector-panel'),
      decoration: BoxDecoration(
        color: inProperties
            ? context.theme.colors.card
            : context.theme.colors.muted,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (selection.length > 1) {
            return selectionInspector(constraints, summaryLayout: summarized);
          }
          if (selected == null || selected!.directory) {
            return folderInspector(
              constraints,
              selected?.normalized ?? folder,
              summaryLayout: summarized,
              inProperties: inProperties,
            );
          }
          return inspectorLayout(
            summaryLayout: summarized,
            preview: summarized
                ? const SizedBox()
                : Container(
                    key: const ValueKey('inspector-preview'),
                    height: (constraints.maxHeight * .375).clamp(90, 270),
                    padding: const EdgeInsets.all(8),
                    child: previewContent(),
                  ),
            information: Column(
              key: const ValueKey('inspector-information'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summarized)
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
                      color: context.theme.colors.mutedForeground,
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
                info('路径', selected!.normalized, literal: true),
              ],
            ),
            actions: selectionActions(),
          );
        },
      ),
    );
  }

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

  Widget selectionInspector(BoxConstraints constraints, {bool? summaryLayout}) {
    final summarized = summaryLayout ?? gallery;
    final entries = selection;
    final count =
        propertyWindowData?['selectionCount'] as int? ?? entries.length;
    final folders =
        propertyWindowData?['folderCount'] as int? ??
        entries.where((entry) => entry.directory).length;
    final roots = entries.where(
      (entry) => !entries.any(
        (parent) =>
            parent.directory &&
            parent.path != entry.path &&
            entry.normalized.startsWith('${parent.normalized}/'),
      ),
    );
    final size =
        propertyWindowData?['size'] as int? ??
        roots.fold<int>(
          0,
          (sum, entry) =>
              sum +
              (entry.directory
                  ? document!.index.sizes[entry.normalized] ?? 0
                  : entry.size),
        );
    return inspectorLayout(
      summaryLayout: summarized,
      preview: SizedBox(
        key: const ValueKey('inspector-preview'),
        height: (constraints.maxHeight * .375).clamp(90, 270),
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
          if (summarized)
            galleryInspectorSummary(
              title: AppText(
                '$count 个项目',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: '${count - folders} 个文件、$folders 个文件夹',
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
              '$count 个项目',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            AppText(
              '${count - folders} 个文件、$folders 个文件夹',
              style: TextStyle(
                fontSize: 12,
                color: context.theme.colors.mutedForeground,
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
          info('项目', '$count 个'),
        ],
      ),
      actions: selectionActions(),
    );
  }

  Widget folderInspector(
    BoxConstraints constraints,
    String summaryFolder, {
    bool? summaryLayout,
    bool inProperties = false,
  }) {
    final summarized = summaryLayout ?? gallery;
    final archive = summaryFolder.isEmpty;
    final title = archive
        ? p.basename(document!.path)
        : p.posix.basename(summaryFolder);
    final entries = itemsInFolder(summaryFolder);
    final totalSize =
        propertyWindowData?['size'] as int? ??
        (archive
            ? document!.index.totalSize
            : document!.index.sizes[summaryFolder] ?? 0);
    final itemCount =
        propertyWindowData?['itemCount'] as int? ??
        (archive
            ? document!.entries.length
            : document!.index.descendants[summaryFolder] ?? 0);
    return inspectorLayout(
      summaryLayout: summarized,
      preview: Container(
        key: const ValueKey('inspector-preview'),
        height: (constraints.maxHeight * .375).clamp(90, 270),
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
          if (summarized)
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
                color: context.theme.colors.mutedForeground,
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
          info(
            '当前层级',
            '${propertyWindowData?['currentCount'] ?? entries.length} 个',
          ),
          info('大小', formatSize(totalSize)),
          info('路径', archive ? document!.path : summaryFolder, literal: true),
          if (archive) info('状态', document!.writable ? '可写入' : '只读'),
          if (archive && document!.supportsComment)
            archiveCommentInformation(inProperties: inProperties),
        ],
      ),
      actions: selectionActions(),
    );
  }

  Widget archiveCommentInformation({bool inProperties = false}) {
    final doc = document!;
    return ArchiveCommentField(
      key: ValueKey('archive-comment-${doc.path}'),
      comment: doc.comment,
      writable: doc.writable,
      presentEditor: true,
      fontSize: inProperties ? 12 : 11,
      busy: busy,
      draft: commentDrafts.putIfAbsent(doc.path, ArchiveCommentDraft.new),
      onSave: (text, original) async {
        try {
          if (propertyWindowData != null) {
            final updatedData = await widget.propertiesAction!('saveComment', {
              'text': text,
              'original': original,
            });
            if (mounted) setState(() => applyPropertiesData(updatedData));
            return;
          }
          final updated = await service.writeComment(
            doc,
            text,
            original: original,
          );
          if (!mounted) return;
          setState(() {
            tabFor(doc.path)?.document = updated;
            if (document?.path == doc.path) document = updated;
          });
          message('注释已保存');
        } catch (failure) {
          if (mounted) message(failure.toString(), error: true);
          rethrow;
        }
      },
    );
  }

  Widget info(String label, String value, {bool literal = false}) => Container(
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
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        Expanded(
          child: Text(
            literal
                ? value
                : translateAppText(value, settings.locale.languageCode),
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
            style: TextStyle(fontSize: 11, color: muted),
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

  bool get hasConfirmation {
    final data = feedback.data;
    return data != null &&
        !data.running &&
        data.actions.keys.any((key) => key != 'dismiss');
  }

  // Keep interactive popovers inside the workspace bounds so they can receive
  // pointer events without changing the footer or the file browser's layout.
  Widget workspaceFeedback(bool desktopLayout) => SafeArea(
    child: LayoutBuilder(
      builder: (context, bounds) => Stack(
        children: [
          if (hasConfirmation && !feedback.nativeVisible && !desktopLayout)
            Positioned.fill(
              child: DesktopDialog(
                key: const ValueKey('inline-task-actions'),
                title: AppText(feedback.data!.title),
                content: AppText(
                  feedback.data!.detail,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
                actions: [
                  for (final action in feedback.data!.actions.entries)
                    DesktopButton(
                      primary: action.key == 'save' || action.key == 'create',
                      onPressed: () => feedback.action(action.key),
                      child: AppText(action.value),
                    ),
                ],
              ),
            )
          else if (hasConfirmation && !feedback.nativeVisible)
            Positioned(
              left: 12,
              right: 12,
              top: !desktopLayout ? 12 : null,
              bottom: !desktopLayout ? 12 : 38,
              child: Align(
                alignment: !desktopLayout
                    ? Alignment.center
                    : Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: (bounds.maxHeight - (!desktopLayout ? 24 : 50))
                        .clamp(0.0, double.infinity),
                  ),
                  child: confirmationPanel(feedback.data!),
                ),
              ),
            )
          else if (queueExpanded)
            Positioned(
              right: 8,
              bottom: 36,
              width: (bounds.maxWidth - 16).clamp(0.0, 360.0),
              child: taskQueuePanel(),
            ),
        ],
      ),
    ),
  );

  Widget confirmationPanel(TaskFeedback data) => FCard.raw(
    key: const ValueKey('inline-task-actions'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              data.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (entryNameInput != null) ...[
              const SizedBox(height: 10),
              DesktopTextField(
                key: const ValueKey('inline-entry-name'),
                controller: entryNameInput!,
                autofocus: true,
                onSubmitted: (_) => feedback.action('create'),
              ),
            ],
            if (data.detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              AppText(
                data.detail,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in data.actions.entries)
                  DesktopButton(
                    primary: action.key == 'save' || action.key == 'create',
                    onPressed: () => feedback.action(action.key),
                    child: AppText(action.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget taskQueuePanel() {
    final tasks = taskQueue.tasks;
    return FCard.raw(
      key: const ValueKey('archive-task-queue'),
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
                            task.failed
                                ? Icons.error_outline
                                : task.paused
                                ? Icons.pause
                                : task.running
                                ? Icons.play_arrow
                                : Icons.schedule,
                            size: 14,
                            color: muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${p.basename(task.archive)} · ${appText(context, task.title)}${task.failed
                                  ? ' · ${appText(context, '失败')}'
                                  : task.paused
                                  ? ' · ${appText(context, '已暂停')}'
                                  : task.cancelled
                                  ? ' · ${appText(context, '正在取消')}'
                                  : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (!task.running &&
                              !task.cancelled &&
                              !task.failed) ...[
                            const SizedBox(width: 8),
                            AppText(
                              '等待中',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                          if (task.failed)
                            DesktopIconButton(
                              tooltip: '重试',
                              icon: const Icon(Icons.refresh, size: 16),
                              onPressed: () => taskQueue.retry(task),
                            ),
                          if (task.canControl)
                            DesktopIconButton(
                              tooltip: task.paused ? '继续' : '暂停',
                              icon: Icon(
                                task.paused ? Icons.play_arrow : Icons.pause,
                                size: 16,
                              ),
                              onPressed: () => task.paused
                                  ? taskQueue.resume(task)
                                  : taskQueue.pause(task),
                            ),
                          DesktopIconButton(
                            key: ValueKey(
                              'cancel-task-${task.archive}-${task.title}',
                            ),
                            tooltip: task.failed ? '关闭' : '取消任务',
                            icon: const Icon(FIcons.x, size: 16),
                            onPressed: task.failed
                                ? () => taskQueue.dismiss(task)
                                : task.canControl
                                ? () => taskQueue.cancel(task)
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget footer(bool desktopLayout) {
    final data = feedback.data;
    final confirmation = hasConfirmation;
    final tasks = taskQueue.tasks;
    final running = tasks.where((task) => task.running).firstOrNull;
    final active = data?.running == true ? data : null;
    final overallProgress = active?.progress ?? progress;
    final showProgress =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        auxiliaryModalDepth.value == 0 &&
        !confirmation &&
        (overallProgress != null || active != null || running != null);
    final operationText = active != null
        ? '${appText(context, active.title)}${active.currentFile.isEmpty ? '' : ' · ${active.currentFile}'}${active.fileProgress == null ? '' : ' · ${appText(context, '当前文件')} ${(active.fileProgress!.clamp(0, 1) * 100).round()}%'}${overallProgress == null ? '' : ' · ${appText(context, '全部进度')} ${(overallProgress.clamp(0, 1) * 100).round()}%'}'
        : running != null
        ? '${appText(context, running.title)} · ${p.basename(running.archive)}'
        : data != null && !confirmation
        ? (data.detail.isEmpty
              ? appText(context, data.title)
              : appText(context, data.detail))
        : appText(context, status);
    final text = running?.paused == true
        ? '${appText(context, '已暂停')} · $operationText'
        : operationText;
    final needsAttention = confirmation || data?.error == true || statusError;
    final attentionKey = '$confirmation|${data?.error}|$statusError|$text';
    final attention =
        needsAttention &&
        active == null &&
        acknowledgedAttention != attentionKey;
    return BreathingStatusBar(
      key: const ValueKey('workspace-status-bar'),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      active: attention,
      tint: confirmation
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
      onTap: () => acknowledgeStatus(attentionKey),
      decoration: BoxDecoration(
        color: context.theme.colors.muted,
        border: Border(top: BorderSide(color: context.theme.colors.border)),
      ),
      child: Row(
        children: [
          if (!desktopLayout) ...[
            DesktopIconButton(
              key: const ValueKey('directory-drawer-toggle'),
              tooltip: '目录',
              icon: const Icon(FIcons.folderTree, size: 17),
              onPressed: () {
                final scaffold = contentScaffold.currentState;
                if (scaffold?.isDrawerOpen == true) {
                  scaffold?.closeDrawer();
                } else {
                  scaffold?.openDrawer();
                }
              },
            ),
            const SizedBox(width: 8),
          ],
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
                      ? Theme.of(context).colorScheme.error
                      : muted,
                ),
              ),
            ),
          ),
          if (showProgress) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: overallProgress == null
                  ? const FProgress()
                  : FDeterminateProgress(value: overallProgress.clamp(0, 1)),
            ),
          ],
          const SizedBox(width: 8),
          DesktopButton(
            key: const ValueKey('task-queue-toggle'),
            flat: true,
            minHeight: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onPressed: () => setState(() => queueExpanded = !queueExpanded),
            child: AppText(
              '队列 (${tasks.length})',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (document != null)
            SizedBox(
              width: desktopLayout ? 132 : 96,
              child: AppTooltip(
                message: '调整图标大小',
                child: DesktopSlider(
                  value: iconSize,
                  showValueTooltip: false,
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
    );
  }
}
