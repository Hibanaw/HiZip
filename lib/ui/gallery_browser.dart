import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/archive_entry.dart';

/// Large preview and a lazily loaded filmstrip. Only small, decoded thumbnails
/// are retained; full extracted image bytes are released after conversion.
class GalleryBrowser extends StatefulWidget {
  const GalleryBrowser({
    super.key,
    required this.document,
    this.enabled = true,
    required this.entries,
    required this.selected,
    required this.thumbnailSize,
    required this.preview,
    required this.loadImage,
    required this.icon,
    required this.item,
    required this.foreground,
    this.trailing,
    this.name,
    this.selectionAreaBuilder,
    this.revealSelection = true,
  });
  final Object document;
  final bool enabled;
  final bool revealSelection;
  final Widget Function(ScrollController, Widget)? selectionAreaBuilder;
  final List<ArchiveEntry> entries;
  final ArchiveEntry? selected;
  final double thumbnailSize;
  final Widget preview;
  final Widget? trailing;
  final Widget Function(ArchiveEntry)? name;
  final Future<Uint8List> Function(ArchiveEntry) loadImage;
  final Widget Function(ArchiveEntry, double) icon;
  final Widget Function(ArchiveEntry, Widget) item;
  final Color Function(ArchiveEntry) foreground;
  @override
  State<GalleryBrowser> createState() => _GalleryBrowserState();
}

class _GalleryBrowserState extends State<GalleryBrowser> {
  final scroll = ScrollController();
  final thumbnailQueues = [Future<void>.value(), Future<void>.value()];
  int nextQueue = 0;
  final thumbnails = <ArchiveEntry, Future<Uint8List?>>{};
  @override
  void initState() {
    super.initState();
    reveal();
  }

  @override
  void didUpdateWidget(GalleryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) ||
        (!oldWidget.enabled && widget.enabled)) {
      thumbnails.clear();
    }
    if (widget.revealSelection &&
        (oldWidget.selected != widget.selected ||
            oldWidget.thumbnailSize != widget.thumbnailSize ||
            !identical(oldWidget.document, widget.document) ||
            !oldWidget.revealSelection)) {
      reveal();
    }
  }

  void reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !scroll.hasClients || !widget.revealSelection) return;
    final index = widget.entries.indexWhere(
      (entry) => entry.path == widget.selected?.path,
    );
    if (index < 0) return;
    final start = index * (widget.thumbnailSize + 24);
    final end = start + widget.thumbnailSize + 24;
    var offset = scroll.offset;
    if (start < offset) offset = start;
    if (end > offset + scroll.position.viewportDimension) {
      offset = end - scroll.position.viewportDimension;
    }
    scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
  });
  Future<Uint8List?> thumbnail(ArchiveEntry entry) {
    if (!thumbnails.containsKey(entry) && thumbnails.length >= 64) {
      thumbnails.remove(thumbnails.keys.first);
    }
    return thumbnails.putIfAbsent(entry, () {
      final document = widget.document;
      final slot = nextQueue++ % thumbnailQueues.length;
      final future = thumbnailQueues[slot].then<Uint8List?>((_) {
        if (!mounted ||
            !widget.enabled ||
            !identical(document, widget.document)) {
          return null;
        }
        return decode(entry);
      });
      thumbnailQueues[slot] = future.then<void>((_) {});
      return future;
    });
  }

  Future<Uint8List?> decode(ArchiveEntry entry) async {
    try {
      final bytes = await widget.loadImage(entry);
      if (!mounted) return null;
      final pixels = (160 * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(160, 640);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final scale = (pixels / math.max(descriptor.width, descriptor.height))
              .clamp(0.0, 1.0);
          final codec = await descriptor.instantiateCodec(
            targetWidth: (descriptor.width * scale).round().clamp(1, pixels),
            targetHeight: (descriptor.height * scale).round().clamp(1, pixels),
          );
          try {
            final frame = await codec.getNextFrame();
            try {
              final data = await frame.image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              return data?.buffer.asUint8List();
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    thumbnails.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = widget.thumbnailSize.clamp(
        24.0,
        (constraints.maxHeight * .35).clamp(24.0, 160.0),
      );
      return Column(
        children: [
          Expanded(
            child: Padding(
              key: const ValueKey('gallery-preview'),
              padding: const EdgeInsets.all(20),
              child: widget.preview,
            ),
          ),
          SizedBox(
            height: size + 42,
            child: selectionArea(
              ListView.builder(
                key: const ValueKey('gallery-filmstrip'),
                controller: scroll,
                scrollCacheExtent: ScrollCacheExtent.pixels(0),
                addAutomaticKeepAlives: false,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                itemExtent: widget.thumbnailSize + 24,
                itemCount:
                    widget.entries.length + (widget.trailing == null ? 0 : 1),
                itemBuilder: (_, index) {
                  if (index == widget.entries.length) return widget.trailing!;
                  final entry = widget.entries[index];
                  final fallback = widget.icon(entry, size);
                  final image =
                      widget.enabled && entry.isImage && entry.canExtract
                      ? FutureBuilder<Uint8List?>(
                          future: thumbnail(entry),
                          builder: (_, snapshot) => snapshot.data == null
                              ? fallback
                              : Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, _, _) => fallback,
                                ),
                        )
                      : fallback;
                  return Tooltip(
                    message: entry.name,
                    child: widget.item(
                      entry,
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          children: [
                            Expanded(child: Center(child: image)),
                            const SizedBox(height: 4),
                            widget.name?.call(entry) ??
                                Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: widget.foreground(entry),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget selectionArea(Widget child) =>
      widget.selectionAreaBuilder?.call(scroll, child) ?? child;
}
