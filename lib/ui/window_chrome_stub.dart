import 'package:flutter/widgets.dart';

Future<void> initializeWindowChrome({int? nativePointer}) async {}
Widget windowDragArea(Widget child) => child;
double windowChromeHeight() => 49;
Widget windowResizeArea(Widget child) => child;
Widget windowLeadingControls() => const SizedBox.shrink();
Widget windowTrailingControls() => const SizedBox.shrink();

Map<String, double> windowFrame() => {};
void configureTaskWindow(Map<String, dynamic> parent) {}
void configureSettingsWindow() {}

void setTaskWindowCloseAction(VoidCallback action) {}
void setWindowClosePreparation(Future<void> Function()? prepare) {}

void setAuxiliaryWindowTitle(String title) {}
