import 'app_localizations.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../services/desktop_integration.dart';

class DesktopMenuAction {
  const DesktopMenuAction(
    this.title,
    this.onPressed, {
    this.children,
    this.checked = false,
    this.enabled = true,
    this.shortcut,
  });
  const DesktopMenuAction.separator()
    : title = '',
      onPressed = null,
      children = null,
      checked = false,
      enabled = false,
      shortcut = null;
  final String title;
  final VoidCallback? onPressed;
  final List<DesktopMenuAction>? children;
  final bool checked;
  final bool enabled;
  final String? shortcut;
  bool get separator => title.isEmpty && children == null;
}

/// Forui applies its offset after overflow correction. Include the pointer
/// offset in the placement calculation so the final menu stays inside the view.
class _ContextMenuOverflow implements FPortalOverflow {
  const _ContextMenuOverflow(this.offset);
  final Offset offset;

  @override
  Offset call(Size view, FPortalChildRect child, FPortalRect portal) =>
      FPortalOverflow.slide(view, child, (
        offset: portal.offset + offset,
        size: portal.size,
        anchor: portal.anchor,
      ));
}

/// Forui menus retain desktop keyboard navigation and nested app choices.
class FileContextMenu extends StatefulWidget {
  static FocusNode? get commandFocus =>
      _FileContextMenuState.opened?.previousFocus ??
      FocusManager.instance.primaryFocus;

  const FileContextMenu({
    super.key,
    required this.child,
    this.childBuilder,
    this.triggerBuilder,
    this.onSelect,
    this.onOpen,
    this.onOpenInHiZip,
    this.onPreview,
    this.onProperties,
    this.onCopy,
    this.onPaste,
    this.onExtract,
    this.onExtractAll,
    this.onExtractAllNamed,
    this.onDelete,
    this.onRename,
    this.onNewFolder,
    this.onNewDocument,
    this.applications,
    this.onOpenWith,
    this.onChooseApplication,
    this.onTouchDragStart,
    this.onTouchDragUpdate,
    this.onTouchDragEnd,
    this.onTouchDragCancel,
    this.touchDragLabel,
    this.applicationOnly = false,
    this.primaryClick = false,
    this.openUpwards = false,
    this.actions,
    this.enabled = true,
  });
  final Widget child;
  final Widget Function(BuildContext, bool, Widget)? childBuilder;
  final Widget Function(BuildContext, bool, VoidCallback)? triggerBuilder;
  final List<DesktopMenuAction>? actions;
  final bool enabled, applicationOnly, primaryClick, openUpwards;
  final VoidCallback? onSelect,
      onOpen,
      onOpenInHiZip,
      onPreview,
      onProperties,
      onCopy,
      onPaste,
      onExtract,
      onExtractAll,
      onExtractAllNamed,
      onDelete,
      onRename,
      onNewFolder,
      onNewDocument,
      onChooseApplication;
  final Future<List<FileApplication>> Function()? applications;
  final void Function(FileApplication)? onOpenWith;
  final VoidCallback? onTouchDragStart;
  final ValueChanged<Offset>? onTouchDragUpdate, onTouchDragEnd;
  final VoidCallback? onTouchDragCancel;
  final String? touchDragLabel;
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
  Timer? touchLongPressTimer, touchDragTimer;
  Offset touchPosition = Offset.zero, touchDownPosition = Offset.zero;
  bool touchHeld = false, touchLongPressed = false, touchDragging = false;
  OverlayEntry? touchDragOverlay;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => close();
  @override
  void dispose() {
    cancelTouch();
    ++request;
    if (opened == this) opened = null;
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    menuFocus.dispose();
    super.dispose();
  }

  void cancelTouch() {
    if (touchDragging) widget.onTouchDragCancel?.call();
    touchLongPressTimer?.cancel();
    touchDragTimer?.cancel();
    touchLongPressTimer = null;
    touchDragTimer = null;
    touchHeld = false;
    touchLongPressed = false;
    touchDragging = false;
    touchDragOverlay?.remove();
    touchDragOverlay = null;
  }

  void touchDown(PointerDownEvent event) {
    if (!widget.enabled ||
        widget.primaryClick ||
        event.kind != PointerDeviceKind.touch) {
      return;
    }
    cancelTouch();
    touchHeld = true;
    touchPosition = event.position;
    touchDownPosition = event.position;
    touchLongPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || !touchHeld) return;
      touchLongPressed = true;
    });
    if (widget.onTouchDragStart != null) {
      touchDragTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted || !touchHeld) return;
        if (!touchLongPressed) {
          touchDragTimer = Timer(const Duration(milliseconds: 100), () {
            if (mounted && touchHeld && touchLongPressed) startTouchDrag();
          });
          return;
        }
        startTouchDrag();
      });
    }
  }

  void startTouchDrag() {
    if (!mounted || !touchHeld || !touchLongPressed) return;
    touchDragTimer = null;
    touchDragging = true;
    showTouchDragFeedback();
    widget.onTouchDragStart?.call();
    widget.onTouchDragUpdate?.call(touchPosition);
  }

  void touchMove(PointerMoveEvent event) {
    if (!touchHeld || event.kind != PointerDeviceKind.touch) return;
    if (!touchLongPressed &&
        (event.position - touchDownPosition).distance > kTouchSlop) {
      cancelTouch();
      return;
    }
    touchPosition = event.position;
    if (touchDragging) widget.onTouchDragUpdate?.call(touchPosition);
    if (touchDragOverlay != null) touchDragOverlay!.markNeedsBuild();
  }

  void touchUp(PointerUpEvent event) {
    if (!touchHeld || event.kind != PointerDeviceKind.touch) return;
    touchPosition = event.position;
    final showMenu = touchLongPressed && !touchDragging;
    if (touchDragging) widget.onTouchDragEnd?.call(touchPosition);
    touchDragging = false;
    cancelTouch();
    if (showMenu) open(touchPosition);
  }

  void touchCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.touch) cancelTouch();
  }

  void showTouchDragFeedback() {
    final overlay = Overlay.of(context, rootOverlay: true);
    touchDragOverlay = OverlayEntry(
      builder: (_) {
        final box = overlay.context.findRenderObject()! as RenderBox;
        final position = box.globalToLocal(touchPosition);
        return Positioned(
          left: position.dx + 12,
          top: position.dy + 12,
          child: IgnorePointer(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_with, size: 16),
                    const SizedBox(width: 6),
                    Text(widget.touchDragLabel ?? appText(context, '拖动')),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(touchDragOverlay!);
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
    // Restore the target before commands inspect whether they act on text or files.
    FocusManager.instance.applyFocusChangesIfNeeded();
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
            style: TextStyle(
              fontSize: 11,
              color: context.theme.colors.mutedForeground,
            ),
          ),
    onPress: action == null ? null : () => invoke(action),
  );

  Size get menuViewport {
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final padding = EdgeInsets.fromViewPadding(
      view.viewPadding,
      view.devicePixelRatio,
    );
    final insets = media.viewInsets;
    return Size(
      math.max(
        1,
        media.size.width -
            math.max(padding.left, insets.left) -
            math.max(padding.right, insets.right) -
            16,
      ),
      math.max(
        1,
        media.size.height -
            math.max(padding.top, insets.top) -
            math.max(padding.bottom, insets.bottom) -
            16,
      ),
    );
  }

  FPopoverMenuStyleDelta get boundedMenuStyle => FPopoverMenuStyleDelta.delta(
    minWidth: math.min(220, menuViewport.width),
    maxWidth: math.min(260, menuViewport.width),
    popoverPadding: const EdgeInsetsGeometryDelta.value(EdgeInsets.all(8)),
    motion: FPopoverMotion.none,
  );

  List<FItemGroupMixin> externalAppItems() => [
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
    if (widget.onChooseApplication != null)
      FItemGroup(children: [item('其他…', widget.onChooseApplication)]),
  ];
  List<FItemGroupMixin> appItems() => widget.onOpenInHiZip == null
      ? externalAppItems()
      : [
          FItemGroup(
            children: [
              item(
                '在 HiZip 中打开',
                widget.onOpenInHiZip,
                icon: const Icon(Icons.archive_outlined, size: 16),
              ),
              if (widget.applications != null ||
                  widget.onChooseApplication != null)
                FSubmenuItem(
                  title: const AppText('其他应用'),
                  submenu: externalAppItems(),
                  submenuStyle: boundedMenuStyle,
                  submenuMaxHeight: menuViewport.height,
                  submenuIntrinsicWidth: false,
                ),
            ],
          ),
        ];
  FItemMixin actionItem(DesktopMenuAction action) => action.children == null
      ? item(
          action.title,
          action.onPressed,
          shortcut: action.shortcut,
          icon: action.checked ? const Icon(Icons.check, size: 14) : null,
        )
      : FSubmenuItem(
          title: AppText(action.title),
          enabled: action.enabled,
          submenu: actionGroups(action.children!),
          submenuStyle: boundedMenuStyle,
          submenuMaxHeight: menuViewport.height,
          submenuIntrinsicWidth: false,
        );

  List<FItemGroupMixin> actionGroups(List<DesktopMenuAction> actions) {
    final groups = <FItemGroupMixin>[];
    var items = <FItemMixin>[];
    for (final action in actions) {
      if (action.separator) {
        if (items.isNotEmpty) groups.add(FItemGroup(children: items));
        items = [];
      } else {
        items.add(actionItem(action));
      }
    }
    if (items.isNotEmpty) groups.add(FItemGroup(children: items));
    return groups;
  }

  List<FItemGroupMixin> menu() {
    if (widget.actions != null) {
      return actionGroups(widget.actions!);
    }
    if (widget.applicationOnly) {
      return appItems();
    }
    return [
      if (widget.onOpen != null ||
          widget.onPreview != null ||
          widget.onOpenInHiZip != null ||
          widget.onOpenWith != null)
        FItemGroup(
          children: [
            if (widget.onOpen != null) item('打开', widget.onOpen),
            if (widget.onOpenInHiZip != null || widget.onOpenWith != null)
              FSubmenuItem(
                title: const AppText('打开方式'),
                submenu: appItems(),
                submenuStyle: boundedMenuStyle,
                submenuMaxHeight: menuViewport.height,
                submenuIntrinsicWidth: false,
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
      if (widget.onExtractAll != null || widget.onExtractAllNamed != null)
        FItemGroup(
          children: [
            if (widget.onExtractAll != null) item('解压全部…', widget.onExtractAll),
            if (widget.onExtractAllNamed != null)
              item('解压全部到同名文件夹…', widget.onExtractAllNamed),
          ],
        ),
      if (widget.onNewFolder != null || widget.onNewDocument != null)
        FItemGroup(
          children: [
            if (widget.onNewFolder != null) item('新建文件夹…', widget.onNewFolder),
            if (widget.onNewDocument != null)
              item('新建空白文档…', widget.onNewDocument),
          ],
        ),
      if (widget.onRename != null)
        FItemGroup(
          children: [
            if (widget.onRename != null) item('重命名…', widget.onRename),
          ],
        ),
      if (widget.onDelete != null)
        FItemGroup(children: [item('删除…', widget.onDelete)]),
      if (widget.onProperties != null)
        FItemGroup(children: [item('属性', widget.onProperties)]),
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
    maxHeight: menuViewport.height,
    menuAnchor: widget.openUpwards ? Alignment.bottomRight : Alignment.topLeft,
    childAnchor: widget.openUpwards ? Alignment.topRight : Alignment.topLeft,
    spacing: const FPortalSpacing.spacing(0),
    overflow: _ContextMenuOverflow(offset),
    // Share Forui's tap region with nested menus so interacting with a submenu
    // does not dismiss its parent. Clicks on the context target still close it.
    hideRegion: FPopoverHideRegion.excludeChild,
    onTapHide: close,
    style: boundedMenuStyle,
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
          onTapDown:
              widget.triggerBuilder == null &&
                  widget.primaryClick &&
                  widget.enabled
              ? (event) {
                  if (opened == this) {
                    close();
                  } else {
                    open(event.globalPosition);
                  }
                }
              : null,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (!widget.primaryClick &&
                  menuShown &&
                  event.buttons == kPrimaryMouseButton) {
                close();
              }
              touchDown(event);
            },
            onPointerMove: touchMove,
            onPointerUp: touchUp,
            onPointerCancel: touchCancel,
            child:
                widget.triggerBuilder?.call(context, menuShown, () {
                  if (opened == this) {
                    close();
                  } else {
                    open(Offset.zero);
                  }
                }) ??
                widget.childBuilder?.call(context, menuShown, widget.child) ??
                widget.child,
          ),
        ),
      ),
    ),
  );
}
