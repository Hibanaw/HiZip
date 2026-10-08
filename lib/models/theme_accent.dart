import 'package:flutter/material.dart';

enum ThemeAccent {
  blue('海蓝', Color(0xff1764cf)),
  purple('紫罗兰', Color(0xff7543c2)),
  teal('青绿', Color(0xff087c80)),
  green('森林绿', Color(0xff28783e)),
  orange('琥珀橙', Color(0xffad520c)),
  rose('玫瑰红', Color(0xffba365f));

  const ThemeAccent(this.label, this.color);
  final String label;
  final Color color;
}
