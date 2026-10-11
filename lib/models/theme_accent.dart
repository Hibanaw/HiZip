import 'package:flutter/material.dart';

enum ThemeAccent {
  // Base colors sampled from the supplied accent palette, in reference order.
  blue('蓝色', Color(0xff007aff)),
  purple('紫色', Color(0xff953d96)),
  rose('粉色', Color(0xfff74f9e)),
  red('红色', Color(0xffe0383e)),
  orange('橙色', Color(0xfff7821b)),
  yellow('黄色', Color(0xffffc726)),
  green('绿色', Color(0xff62ba46)),
  gray('灰色', Color(0xff989898));

  const ThemeAccent(this.label, this.color);
  final String label;
  final Color color;

  Color colorFor(Brightness brightness) => color;

  static ThemeAccent fromName(String? name) {
    // Keep existing preferences when replacing the old teal option.
    if (name == 'teal') return green;
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => orange,
    );
  }
}
