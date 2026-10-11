import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../models/selection_highlight.dart';
import '../models/theme_accent.dart';
import 'app_localizations.dart';

FThemeData _desktopForuiTheme(
  Brightness brightness, {
  Color? accent,
  Color? onAccent,
}) {
  final colors =
      (brightness == Brightness.dark
              ? FThemes.neutral.dark.desktop.colors
              : FThemes.neutral.light.desktop.colors)
          .copyWith(primary: accent, primaryForeground: onAccent);
  final typography = FTypography(
    fontFamily: '.AppleSystemUIFont',
    xs: TextStyle(
      color: colors.foreground,
      fontFamily: '.AppleSystemUIFont',
      fontSize: 12,
      height: 1.25,
    ),
    sm: TextStyle(
      color: colors.foreground,
      fontFamily: '.AppleSystemUIFont',
      fontSize: 13,
      height: 1.3,
    ),
    md: TextStyle(
      color: colors.foreground,
      fontFamily: '.AppleSystemUIFont',
      fontSize: 15,
      height: 1.4,
    ),
  );
  return FThemeData(
    touch: false,
    colors: colors,
    typography: typography,
    style: FStyle.inherit(colors: colors, typography: typography, touch: false)
        .copyWith(
          borderRadius: const FBorderRadius(
            xs: BorderRadius.all(Radius.circular(5)),
            sm: BorderRadius.all(Radius.circular(5)),
            md: BorderRadius.all(Radius.circular(5)),
          ),
        ),
  );
}

final desktopForuiTheme = _desktopForuiTheme(Brightness.light);
final desktopForuiDarkTheme = _desktopForuiTheme(Brightness.dark);

Widget foruiBuilder(BuildContext context, Widget? child) => FTheme(
  data: _desktopForuiTheme(
    Theme.of(context).brightness,
    accent: Theme.of(context).colorScheme.primary,
    onAccent: Theme.of(context).colorScheme.onPrimary,
  ),
  child: child ?? const SizedBox(),
);

/// Inputs reserve six pixels above and below the scaled text line.
double desktopInputHeight(
  BuildContext context, {
  double fontSize = 12,
  double minimum = 28,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'Ag国',
      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontSize: fontSize,
        height: 1.3,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = (painter.height + 12).ceilToDouble();
  painter.dispose();
  return height.clamp(minimum, double.infinity);
}

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
    this.borderRadius = const BorderRadius.all(Radius.circular(5)),
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool flat, primary, active;
  final double minHeight;
  final EdgeInsets padding;
  final String? tooltip;
  final Color? foreground;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final emphasized = active || primary;
    final scheme = Theme.of(context).colorScheme;
    final colors = FTheme.of(context).colors;
    final background = primary
        ? scheme.primary
        : active
        ? scheme.primaryContainer
        : flat
        ? Colors.transparent
        : colors.card;
    final hoveredBackground = emphasized
        ? Color.lerp(background, Colors.black, .08)!
        : scheme.primary.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .10,
          );
    final color = emphasized
        ? onPressed == null
              ? colors.mutedForeground
              : primary
              ? scheme.onPrimary
              : scheme.onPrimaryContainer
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
        decoration: FVariants.from(
          BoxDecoration(
            color: background,
            borderRadius: borderRadius,
            border: !emphasized && !flat
                ? Border.all(color: colors.border)
                : null,
          ),
          variants: {
            [FTappableVariant.hovered, FTappableVariant.pressed]:
                DecorationDelta.boxDelta(color: hoveredBackground),
            [FTappableVariant.disabled]: DecorationDelta.boxDelta(
              color: colors.disable(background),
            ),
          },
        ),
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
          final interacting =
              data.variants.contains(FTappableVariant.hovered) ||
              data.variants.contains(FTappableVariant.pressed);
          final contentColor =
              color ??
              (onPressed != null && interacting
                  ? desktopAccentForeground(
                      context,
                      background: Color.alphaBlend(
                        hoveredBackground,
                        colors.card,
                      ),
                    )
                  : null);
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: DefaultTextStyle.merge(
                  style: text.copyWith(color: contentColor),
                  child: IconTheme(
                    data: contentColor == null
                        ? icon
                        : icon.copyWith(color: contentColor),
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
    this.borderRadius = const BorderRadius.all(Radius.circular(5)),
  });
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final BorderRadius borderRadius;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 28,
    child: DesktopButton(
      flat: true,
      active: active,
      borderRadius: borderRadius,
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      onPressed: onPressed,
      child: icon,
    ),
  );
}

/// Forui fields share the same compact sizing in toolbars, editors and dialogs.
class DesktopTextField extends StatelessWidget {
  const DesktopTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.error,
    this.prefix,
    this.suffix,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.expands = false,
    this.maxLines = 1,
    this.fontSize = 12,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 6,
    ),
    this.fontFamily,
    this.textAlign = TextAlign.start,
    this.groupId = EditableText,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Widget? label, error, prefix, suffix;
  final String? hint, fontFamily;
  final bool autofocus, enabled, readOnly, obscureText, expands;
  final int? maxLines;
  final double fontSize;
  final EdgeInsets contentPadding;
  final TextAlign textAlign;
  final Object groupId;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TapRegionCallback? onTapOutside;

  @override
  Widget build(BuildContext context) {
    // FTextField 0.21.3 merges EditableText semantics, which asserts in the
    // current Flutter SDK. Use its theme styles with the native editing field
    // so text input and accessibility keep their own semantics nodes.
    final style = context.theme.textFieldStyles.resolve({
      FTextFieldSizeVariant.sm,
      context.platformVariant,
    });
    Set<FTextFieldVariant> variants(Set<WidgetState> states) => {
      context.platformVariant as FTextFieldVariant,
      if (states.contains(WidgetState.disabled)) FTextFieldVariant.disabled,
      if (states.contains(WidgetState.focused)) FTextFieldVariant.focused,
      if (states.contains(WidgetState.hovered)) FTextFieldVariant.hovered,
      if (states.contains(WidgetState.pressed)) FTextFieldVariant.pressed,
      if (error != null) FTextFieldVariant.error,
    };
    final color = desktopAccentForeground(context);
    Widget field = TextField(
      controller: controller,
      groupId: groupId,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      expands: expands,
      maxLines: maxLines,
      textAlign: textAlign,
      textAlignVertical: expands
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      enableSuggestions: false,
      autocorrect: false,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      cursorColor: color,
      keyboardAppearance: style.keyboardAppearance,
      style: style.contentTextStyle
          .resolve({
            context.platformVariant,
            if (!enabled) FTextFieldVariant.disabled,
          })
          .copyWith(
            fontFamily: fontFamily ?? '.AppleSystemUIFont',
            fontSize: fontSize,
            height: 1.3,
            leadingDistribution: TextLeadingDistribution.even,
          ),
      decoration: InputDecoration(
        isDense: true,
        visualDensity: VisualDensity.standard,
        contentPadding: contentPadding,
        hintText: hint,
        hintStyle: WidgetStateTextStyle.resolveWith(
          (states) => style.hintTextStyle.resolve(variants(states)),
        ),
        filled: true,
        fillColor: WidgetStateColor.resolveWith(
          (states) =>
              style.color.resolve(variants(states)) ?? Colors.transparent,
        ),
        prefixIcon: prefix,
        suffixIcon: suffix,
        prefixIconConstraints: const BoxConstraints(),
        suffixIconConstraints: const BoxConstraints(),
        border: WidgetStateInputBorder.resolveWith(
          (states) => style.border.resolve(variants(states)),
        ),
        enabledBorder: style.border.resolve(variants({})),
        focusedBorder: style.border.resolve(variants({WidgetState.focused})),
        disabledBorder: style.border.resolve(variants({WidgetState.disabled})),
      ),
    );
    if (label != null || error != null) {
      field = FLabel(
        layout: FLabelLayout.vertical,
        style: style,
        label: label,
        error: error,
        expands: expands,
        variants: {
          context.platformVariant as FFormFieldVariant,
          if (!enabled) FFormFieldVariant.disabled,
          if (error != null) FFormFieldVariant.error,
        },
        child: field,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
        child: field,
      ),
    );
  }
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
              const Icon(FIcons.chevronDown, size: 16),
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
    this.showValueTooltip = true,
    this.onChanged,
  });
  final double value, min, max;
  final int? divisions;
  final bool showValueTooltip;
  final ValueChanged<double>? onChanged;

  double normalize(double value) => ((value - min) / (max - min)).clamp(0, 1);
  double denormalize(double fraction) {
    if (divisions != null) {
      fraction = (fraction * divisions!).round() / divisions!;
    }
    return (min + fraction * (max - min)).clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FTheme.of(context).colors;
    final accent = desktopAccentForeground(context);
    return FSlider(
      enabled: onChanged != null,
      control: FSliderControl.liftedContinuous(
        value: FSliderValue(max: normalize(value)),
        stepPercentage: divisions == null ? 1 / (max - min) : 1 / divisions!,
        onChange: (value) => onChanged?.call(denormalize(value.max)),
      ),
      trackHitRegionCrossExtent: 24,
      tooltipControls: showValueTooltip
          ? const FSliderTooltipControls()
          : const FSliderTooltipControls.disabled(),
      style: FSliderStyleDelta.delta(
        activeColor: FVariants(
          accent,
          variants: {
            [FSliderVariant.disabled]: colors.disable(accent, colors.secondary),
          },
        ),
        thumbStyle: FSliderThumbStyleDelta.delta(
          color: FVariants.all(colors.card),
          borderColor: FVariants(
            accent,
            variants: {
              [FSliderVariant.disabled]: colors.disable(accent),
            },
          ),
        ),
        crossAxisExtent: 2,
        thumbSize: 12,
        childPadding: const EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
      tooltipBuilder: (_, fraction) =>
          Text(denormalize(fraction).round().toString()),
      semanticValueFormatterCallback: (fraction) =>
          denormalize(fraction).round().toString(),
    );
  }
}

class DesktopDialogScope extends InheritedWidget {
  const DesktopDialogScope({super.key, required super.child});
  @override
  bool updateShouldNotify(DesktopDialogScope oldWidget) => false;
}

class DesktopDialog extends StatelessWidget {
  const DesktopDialog({
    super.key,
    required this.title,
    this.content,
    required this.actions,
    this.maxWidth = 460,
  });
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final inWindow =
        context.dependOnInheritedWidgetOfExactType<DesktopDialogScope>() !=
        null;
    if (inWindow || MediaQuery.sizeOf(context).width < 800) {
      return Material(
        key: const ValueKey('auxiliary-fullscreen-dialog'),
        color: context.theme.colors.card,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.theme.colors.foreground,
                    ),
                    child: title,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: content ?? const SizedBox.shrink(),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return FDialog(
      constraints: BoxConstraints(minWidth: 280, maxWidth: maxWidth),
      direction: Axis.horizontal,
      title: title,
      body: content,
      // Forui orders the primary action first, then reverses horizontal actions.
      actions: actions.reversed.toList(),
    );
  }
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

ThemeData desktopTheme({
  Brightness brightness = Brightness.light,
  ThemeAccent accent = ThemeAccent.orange,
}) {
  final dark = brightness == Brightness.dark;
  final primary = accent.colorFor(brightness);
  const onPrimary = Colors.white;
  final neutral = dark
      ? FThemes.neutral.dark.desktop.colors
      : FThemes.neutral.light.desktop.colors;
  final controlAccent = _accentForeground(primary, brightness);
  final surface = neutral.background;
  final foreground = neutral.foreground;
  final secondaryText = neutral.mutedForeground;
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primary,
        onPrimaryContainer: onPrimary,
        secondary: primary,
        onSecondary: onPrimary,
        surface: surface,
        onSurface: foreground,
        error: dark ? const Color(0xfff28b82) : const Color(0xffb00020),
        onError: dark ? surface : Colors.white,
      );
  // Construct each brightness independently so Material defaults (dialogs,
  // inputs, icons and disabled controls) never inherit the other theme.
  return ThemeData(
    useMaterial3: false,
    brightness: brightness,
    colorScheme: scheme,
    primaryColor: primary,
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    cardColor: surface,
    fontFamily: '.AppleSystemUIFont',
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    checkboxTheme: CheckboxThemeData(
      checkColor: WidgetStatePropertyAll(onPrimary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: controlAccent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: dark ? null : FilledButton.styleFrom(overlayColor: Colors.black),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: controlAccent,
      selectionColor: primary.withValues(alpha: dark ? .35 : .18),
      selectionHandleColor: controlAccent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      // Compact density subtracts eight pixels from the painted input and can
      // leave its border shorter than the text/caret inside a fixed-height slot.
      visualDensity: VisualDensity.standard,
      isDense: true,
      filled: true,
      fillColor: neutral.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      hintStyle: TextStyle(color: secondaryText),
      labelStyle: TextStyle(color: secondaryText),
      floatingLabelStyle: TextStyle(color: controlAccent),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(
          color: dark ? const Color(0xff55565c) : const Color(0xffc7c8cd),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(color: controlAccent),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(
          color: dark ? const Color(0xff414248) : const Color(0xffdedee2),
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: controlAccent,
      thumbColor: controlAccent,
      inactiveTrackColor: controlAccent.withValues(alpha: .24),
      overlayColor: controlAccent.withValues(alpha: .16),
      valueIndicatorColor: neutral.card,
      valueIndicatorTextStyle: TextStyle(fontSize: 12, color: foreground),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: controlAccent),
    textTheme: TextTheme(
      bodyLarge: TextStyle(
        fontSize: 13,
        height: 1.3,
        leadingDistribution: TextLeadingDistribution.even,
        color: foreground,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: foreground),
      bodySmall: TextStyle(fontSize: 11, color: secondaryText),
    ),
    dividerColor: neutral.border,
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: TextStyle(fontSize: 11, color: foreground),
      decoration: BoxDecoration(
        color: neutral.card,
        border: Border.all(color: neutral.border),
        borderRadius: const BorderRadius.all(Radius.circular(5)),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(2),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? (dark ? const Color(0xffa0a0a5) : const Color(0xff93939a))
            : (dark ? const Color(0xff6c6d74) : const Color(0xffb5b5bb)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(),
      surfaceTintColor: Colors.transparent,
    ),
  );
}

double _contrastRatio(Color a, Color b) {
  final x = a.computeLuminance() + .05;
  final y = b.computeLuminance() + .05;
  return x > y ? x / y : y / x;
}

Color _accentForeground(
  Color primary,
  Brightness brightness, {
  Color? background,
}) {
  final dark = brightness == Brightness.dark;
  final surface =
      background ??
      (dark
          ? FThemes.neutral.dark.desktop.colors.background
          : FThemes.neutral.light.desktop.colors.background);
  final target = dark ? Colors.white : Colors.black;
  // Preserve the reference fill; adjust only standalone text and thin strokes.
  for (var step = 0; step <= 100; step++) {
    final color = Color.lerp(primary, target, step / 100)!;
    if (_contrastRatio(color, surface) >= 4.5) return color;
  }
  return target;
}

/// Readable accent text and strokes on either workspace surface.
Color desktopAccentForeground(BuildContext context, {Color? background}) =>
    _accentForeground(
      Theme.of(context).colorScheme.primary,
      Theme.of(context).brightness,
      background: background,
    );

Color desktopColor(BuildContext context, int light, int dark) =>
    Color(Theme.of(context).brightness == Brightness.dark ? dark : light);

Color desktopSelectionBackground(BuildContext context) =>
    context.theme.colors.secondary;

Color desktopSelectionForeground(
  BuildContext context, {
  bool secondary = false,
}) {
  final colors = context.theme.colors;
  final foreground = secondary ? colors.mutedForeground : colors.foreground;
  for (var step = 0; step <= 100; step++) {
    final color = Color.lerp(foreground, colors.foreground, step / 100)!;
    if (_contrastRatio(color, colors.secondary) >= 4.5) return color;
  }
  return colors.foreground;
}

Color fileSelectionBackground(
  BuildContext context,
  SelectionHighlight highlight,
) => highlight == SelectionHighlight.blue
    ? Theme.of(context).colorScheme.primaryContainer
    : desktopSelectionBackground(context);

Color fileSelectionForeground(
  BuildContext context,
  SelectionHighlight highlight, {
  bool secondary = false,
}) => highlight == SelectionHighlight.blue
    ? Theme.of(context).colorScheme.onPrimaryContainer
    : desktopSelectionForeground(context, secondary: secondary);
