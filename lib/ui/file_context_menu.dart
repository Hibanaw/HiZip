import 'app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../services/desktop_integration.dart';

class DesktopMenuAction {
  const DesktopMenuAction(this.title, this.onPressed);
  final String title;
  final VoidCallback? onPressed;
}

/// Forui menus retain desktop keyboard navigation and nested app choices.
class FileContextMenu extends StatefulWidget {
  const FileContextMenu({
    super.key,
    required this.child,
    this.childBuilder,
    this.onSelect,
    this.onOpen,
    this.onPreview,
    this.onCopy,
    this.onPaste,
    this.onExtract,
    this.onDelete,
    this.onNewFolder,
    this.onNewDocument,
    this.applications,
    this.onOpenWith,
    this.onChooseApplication,
    this.applicationOnly = false,
    this.primaryClick = false,
    this.openUpwards = false,
    this.actions,
    this.enabled = true,
  });
  final Widget child;
  final Widget Function(BuildContext, bool, Widget)? childBuilder;
  final List<DesktopMenuAction>? actions;
  final bool enabled, applicationOnly, primaryClick, openUpwards;
  final VoidCallback? onSelect,
      onOpen,
      onPreview,
      onCopy,
      onPaste,
      onExtract,
      onDelete,
      onNewFolder,
      onNewDocument,
      onChooseApplication;
  final Future<List<FileApplication>> Function()? applications;
  final void Function(FileApplication)? onOpenWith;
  @override
  State<FileContextMenu> createState() => _FileContextMenuState();
}

class _FileContextMenuState extends State<FileContextMenu>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static _FileContextMenuState? opened;
  late final controller = FPopoverController(vsync: this);
  late final FocusScopeNode menuFocus = FocusScopeNode(
    debugLabel: 'archive context menu',
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        menuFocus.nextFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        menuFocus.previousFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  Offset offset = Offset.zero;
  List<FileApplication>? apps;
  int request = 0;
  bool menuShown = false;
  FocusNode? previousFocus;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => close();
  @override
  void dispose() {
    ++request;
    if (opened == this) opened = null;
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    menuFocus.dispose();
    super.dispose();
  }

  void close() {
    ++request;
    unawaited(controller.hide());
    if (opened == this) opened = null;
    if (previousFocus?.context != null) previousFocus?.requestFocus();
    previousFocus = null;
  }

  void invoke(VoidCallback? action) {
    close();
    action?.call();
  }

  void open(Offset position) {
    if (!widget.enabled) return;
    opened?.close();
    widget.onSelect?.call();
    previousFocus = FocusManager.instance.primaryFocus;
    final box = context.findRenderObject()! as RenderBox;
    setState(() {
      offset = widget.primaryClick
          ? widget.openUpwards
                ? Offset.zero
                : Offset(0, box.size.height)
          : box.globalToLocal(position);
      apps = null;
    });
    opened = this;
    final token = ++request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == request) unawaited(controller.show());
    });
    widget.applications?.call().then(
      (value) {
        if (mounted && token == request) setState(() => apps = value);
      },
      onError: (Object _) {
        if (mounted && token == request) setState(() => apps = []);
      },
    );
  }

  String command(String key) =>
      Theme.of(context).platform == TargetPlatform.macOS
      ? '⌘$key'
      : 'Ctrl+$key';
  FItem item(
    String title,
    VoidCallback? action, {
    String? shortcut,
    Widget? icon,
  }) => FItem(
    title: AppText(title),
    enabled: action != null,
    prefix: icon,
    suffix: shortcut == null
        ? null
        : AppText(
            shortcut,
            style: const TextStyle(fontSize: 11, color: Color(0xff8b8b8b)),
          ),
    onPress: action == null ? null : () => invoke(action),
  );
  List<FItemGroupMixin> appItems() => [
    FItemGroup(
      children: [
        if (apps == null) item('正在读取应用…', null),
        for (final app in apps ?? <FileApplication>[])
          item(
            '${app.name}${app.isDefault ? '（默认）' : ''}',
            () => widget.onOpenWith?.call(app),
            icon: app.icon == null
                ? null
                : Image.memory(app.icon!, width: 16, height: 16),
          ),
      ],
    ),
    FItemGroup(children: [item('其他…', widget.onChooseApplication)]),
  ];
  List<FItemGroupMixin> menu() {
    if (widget.actions != null) {
      return [
        FItemGroup(
          children: [
            for (final action in widget.actions!)
              item(action.title, action.onPressed),
          ],
        ),
      ];
    }
    if (widget.applicationOnly) {
      return appItems();
    }
    return [
      if (widget.onOpen != null ||
          widget.onPreview != null ||
          widget.onOpenWith != null)
        FItemGroup(
          children: [
            if (widget.onOpen != null) item('打开', widget.onOpen),
            if (widget.onOpenWith != null)
              FSubmenuItem(
                title: const AppText('打开方式'),
                submenu: appItems(),
                submenuStyle: const FPopoverMenuStyleDelta.delta(
                  motion: FPopoverMotion.none,
                ),
              ),
            if (widget.onPreview != null)
              item('快速查看', widget.onPreview, shortcut: '空格'),
          ],
        ),
      FItemGroup(
        children: [
          if (widget.onCopy != null)
            item('复制', widget.onCopy, shortcut: command('C')),
          item('粘贴', widget.onPaste, shortcut: command('V')),
        ],
      ),
      if (widget.onExtract != null)
        FItemGroup(children: [item('解压所选', widget.onExtract)]),
      if (widget.onNewFolder != null || widget.onNewDocument != null)
        FItemGroup(
          children: [
            if (widget.onNewFolder != null) item('新建文件夹…', widget.onNewFolder),
            if (widget.onNewDocument != null)
              item('新建空白文档…', widget.onNewDocument),
          ],
        ),
      if (widget.onDelete != null)
        FItemGroup(children: [item('删除…', widget.onDelete)]),
    ];
  }

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    control: FPopoverControl.managed(
      controller: controller,
      onChange: (shown) {
        if (mounted && menuShown != shown) setState(() => menuShown = shown);
      },
    ),
    menu: menu(),
    autofocus: true,
    focusNode: menuFocus,
    intrinsicWidth: false,
    maxHeight: MediaQuery.sizeOf(context).height - 16,
    menuAnchor: widget.openUpwards ? Alignment.bottomRight : Alignment.topLeft,
    childAnchor: widget.openUpwards ? Alignment.topRight : Alignment.topLeft,
    offset: offset,
    spacing: const FPortalSpacing.spacing(0),
    overflow: FPortalOverflow.slide,
    hideRegion: widget.primaryClick
        ? FPopoverHideRegion.excludeChild
        : FPopoverHideRegion.anywhere,
    onTapHide: close,
    style: const FPopoverMenuStyleDelta.delta(
      minWidth: 220,
      maxWidth: 260,
      motion: FPopoverMotion.none,
    ),
    child: Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              close();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: widget.enabled
              ? (event) => open(event.globalPosition)
              : null,
          onTapDown: widget.primaryClick && widget.enabled
              ? (event) {
                  if (opened == this) {
                    close();
                  } else {
                    open(event.globalPosition);
                  }
                }
              : null,
          child:
              widget.childBuilder?.call(context, menuShown, widget.child) ??
              widget.child,
        ),
      ),
    ),
  );
}
