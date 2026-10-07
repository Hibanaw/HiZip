import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../models/selection_highlight.dart';
import 'app_localizations.dart';

FThemeData _desktopForuiTheme(Brightness brightness) => FThemeData(
  touch: false,
  style:
      (brightness == Brightness.dark
              ? FThemes.neutral.dark.desktop.style
              : FThemes.neutral.light.desktop.style)
          .copyWith(
            borderRadius: const FBorderRadius(
              xs: BorderRadius.all(Radius.circular(5)),
              sm: BorderRadius.all(Radius.circular(5)),
              md: BorderRadius.all(Radius.circular(5)),
            ),
          ),
  colors: brightness == Brightness.dark
      ? FThemes.neutral.dark.desktop.colors
      : FThemes.neutral.light.desktop.colors,
  typography: FTypography(
    fontFamily: '.AppleSystemUIFont',
    xs: const TextStyle(fontSize: 12, height: 1.25),
    sm: const TextStyle(fontSize: 13, height: 1.3),
    md: const TextStyle(fontSize: 15, height: 1.4),
  ),
);

final desktopForuiTheme = _desktopForuiTheme(Brightness.light);
final desktopForuiDarkTheme = _desktopForuiTheme(Brightness.dark);

Widget foruiBuilder(BuildContext context, Widget? child) => FTheme(
  data: Theme.of(context).brightness == Brightness.dark
      ? desktopForuiDarkTheme
      : desktopForuiTheme,
  child: child ?? const SizedBox(),
);

/// Keeps the workspace's compact toolbar sizing while Forui owns interaction,
/// keyboard focus, disabled states and visual styling.
class DesktopButton extends StatelessWidget {
  const DesktopButton({
    super.key,
    required this.child,
    this.onPressed,
    this.flat = false,
    this.primary = false,
    this.active = false,
    this.minHeight = 28,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.tooltip,
    this.foreground,
    this.focusNode,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool flat, primary, active;
  final double minHeight;
  final EdgeInsets padding;
  final String? tooltip;
  final Color? foreground;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final emphasized = active || primary;
    final background = desktopSelectionBackground(context);
    final colors = FTheme.of(context).colors;
    final color = emphasized
        ? onPressed == null
              ? desktopColor(context, 0xff777780, 0xffa0a0a5)
              : desktopSelectionForeground(context)
        : foreground;
    Widget button = FButton.raw(
      variant: primary
          ? FButtonVariant.primary
          : flat
          ? FButtonVariant.ghost
          : FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      selected: active,
      style: FButtonStyleDelta.delta(
        decoration: emphasized
            ? FVariants.from(
                BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(5),
                ),
                variants: {
                  [FTappableVariant.hovered, FTappableVariant.pressed]:
                      DecorationDelta.boxDelta(color: colors.hover(background)),
                  [FTappableVariant.disabled]: DecorationDelta.boxDelta(
                    color: colors.disable(background),
                  ),
                },
              )
            : null,
        contentStyle: FButtonContentStyleDelta.delta(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsetsGeometryDelta.value(padding),
        ),
      ),
      focusNode: focusNode,
      onPress: onPressed,
      child: Builder(
        builder: (context) {
          final data = FButtonData.of(context);
          final content = data.style.contentStyle;
          final text = content.textStyle.resolve(data.variants);
          final icon = content.iconStyle.resolve(data.variants);
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: DefaultTextStyle.merge(
                  style: text.copyWith(color: color),
                  child: IconTheme(
                    data: color == null ? icon : icon.copyWith(color: color),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: appText(context, tooltip!), child: button);
    }
    return button;
  }
}

class DesktopIconButton extends StatelessWidget {
  const DesktopIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.active = false,
  });
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 28,
    child: DesktopButton(
      flat: true,
      active: active,
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      onPressed: onPressed,
      child: icon,
    ),
  );
}

/// Controlled Forui selection shared by desktop settings. Labels use the app locale.
/// Uses a button/menu because FSelect 0.21.3 merges its input semantics with
/// portal content and triggers a Flutter semantics assertion when expanded.
class DesktopSelect<T> extends StatefulWidget {
  const DesktopSelect({
    super.key,
    required this.items,
    required this.value,
    this.onChanged,
  });
  final Map<String, T> items;
  final T value;
  final ValueChanged<T>? onChanged;
  @override
  State<DesktopSelect<T>> createState() => _DesktopSelectState<T>();
}

class _DesktopSelectState<T> extends State<DesktopSelect<T>>
    with SingleTickerProviderStateMixin {
  late final controller = FPopoverController(vsync: this);
  late final FocusScopeNode menuFocus = FocusScopeNode(
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        controller.hide();
        buttonFocus.requestFocus();
        return KeyEventResult.handled;
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
  final buttonFocus = FocusNode();
  @override
  void dispose() {
    controller.dispose();
    menuFocus.dispose();
    buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = widget.items.entries
          .firstWhere((entry) => entry.value == widget.value)
          .key;
      return FPopoverMenu(
        control: FPopoverControl.managed(controller: controller),
        autofocus: true,
        focusNode: menuFocus,
        menuAnchor: Alignment.topLeft,
        childAnchor: Alignment.bottomLeft,
        maxHeight: 300,
        style: FPopoverMenuStyleDelta.delta(
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
        ),
        menu: [
          FItemGroup(
            children: [
              for (final entry in widget.items.entries)
                FItem(
                  title: AppText(entry.key),
                  autofocus: entry.value == widget.value,
                  suffix: entry.value == widget.value
                      ? const Icon(Icons.check, size: 14)
                      : null,
                  enabled: widget.onChanged != null,
                  onPress: () {
                    controller.hide();
                    buttonFocus.requestFocus();
                    widget.onChanged?.call(entry.value);
                  },
                ),
            ],
          ),
        ],
        child: DesktopButton(
          focusNode: buttonFocus,
          minHeight: 32,
          onPressed: widget.onChanged == null
              ? null
              : () => controller.toggle(),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
        ),
      );
    },
  );
}

/// Keeps each browser mode's numeric range while Forui handles pointer and keyboard input.
class DesktopSlider extends StatelessWidget {
  const DesktopSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
  });
  final double value, min, max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  double normalize(double value) => ((value - min) / (max - min)).clamp(0, 1);
  double denormalize(double fraction) {
    if (divisions != null) {
      fraction = (fraction * divisions!).round() / divisions!;
    }
    return (min + fraction * (max - min)).clamp(min, max);
  }

  @override
  Widget build(BuildContext context) => FSlider(
    enabled: onChanged != null,
    control: FSliderControl.liftedContinuous(
      value: FSliderValue(max: normalize(value)),
      stepPercentage: divisions == null ? 1 / (max - min) : 1 / divisions!,
      onChange: (value) => onChanged?.call(denormalize(value.max)),
    ),
    trackHitRegionCrossExtent: 24,
    style: const FSliderStyleDelta.delta(
      crossAxisExtent: 2,
      thumbSize: 12,
      childPadding: EdgeInsetsGeometryDelta.value(
        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    ),
    tooltipBuilder: (_, fraction) =>
        Text(denormalize(fraction).round().toString()),
    semanticValueFormatterCallback: (fraction) =>
        denormalize(fraction).round().toString(),
  );
}

class DesktopDialog extends StatelessWidget {
  const DesktopDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => FDialog(
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 460),
    title: title,
    body: content,
    actions: actions,
  );
}

class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => axisDirectionToAxis(details.direction) == Axis.horizontal
      ? child
      : Scrollbar(controller: details.controller, child: child);
}

ThemeData desktopTheme({Brightness brightness = Brightness.light}) =>
    brightness == Brightness.dark
    ? desktopTheme().copyWith(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xff6aa4ff),
          surface: Color(0xff202124),
          onSurface: Color(0xffeeeeef),
        ),
        scaffoldBackgroundColor: const Color(0xff202124),
        textTheme: desktopTheme().textTheme.apply(
          bodyColor: const Color(0xffeeeeef),
          displayColor: const Color(0xffeeeeef),
        ),
        dividerColor: const Color(0xff414248),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 500),
          textStyle: TextStyle(fontSize: 11, color: Color(0xffeeeeef)),
          decoration: BoxDecoration(
            color: Color(0xff34353a),
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
      )
    : ThemeData(
        useMaterial3: false,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xff3478f6),
          secondary: Color(0xff62636a),
          surface: Colors.white,
          onSurface: Color(0xff303036),
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: '.AppleSystemUIFont',
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 13, color: Color(0xff303036)),
          bodySmall: TextStyle(fontSize: 11, color: Color(0xff777780)),
        ),
        dividerColor: const Color(0xffdedee2),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 500),
          textStyle: TextStyle(fontSize: 11, color: Color(0xff303036)),
          decoration: BoxDecoration(
            color: Color(0xffffffe9),
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xffbdbdb5), width: .5),
            ),
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thickness: const WidgetStatePropertyAll(6),
          radius: const Radius.circular(2),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? const Color(0xff93939a)
                : const Color(0xffb5b5bb),
          ),
        ),
        dialogTheme: const DialogThemeData(
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        drawerTheme: const DrawerThemeData(
          shape: RoundedRectangleBorder(),
          surfaceTintColor: Colors.transparent,
        ),
      );

Color desktopColor(BuildContext context, int light, int dark) =>
    Color(Theme.of(context).brightness == Brightness.dark ? dark : light);

Color desktopSelectionBackground(BuildContext context) =>
    desktopColor(context, 0xffe4e5e7, 0xff424348);

Color desktopSelectionForeground(
  BuildContext context, {
  bool secondary = false,
}) => secondary
    ? desktopColor(context, 0xff55565c, 0xffd1d1d6)
    : desktopColor(context, 0xff303036, 0xfff3f3f5);

Color fileSelectionBackground(
  BuildContext context,
  SelectionHighlight highlight,
) => highlight == SelectionHighlight.blue
    ? desktopColor(context, 0xff0063d5, 0xff005ac7)
    : desktopSelectionBackground(context);

Color fileSelectionForeground(
  BuildContext context,
  SelectionHighlight highlight, {
  bool secondary = false,
}) => highlight == SelectionHighlight.blue
    ? (secondary ? const Color(0xffe5efff) : Colors.white)
    : desktopSelectionForeground(context, secondary: secondary);
