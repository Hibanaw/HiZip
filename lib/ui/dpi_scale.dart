import 'package:flutter/material.dart';

class DpiScale extends StatelessWidget {
  const DpiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final factor = scale.clamp(.75, 1.5).toDouble();
    final media = MediaQuery.of(context);
    final systemScale = media.textScaler.scale(1);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(systemScale * factor)),
      child: child,
    );
  }
}
