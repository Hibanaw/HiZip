import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libadwaita/libadwaita.dart' as adw;

import 'app_localizations.dart';
import 'desktop_widgets.dart';

class WindowCloseButton extends StatelessWidget {
  const WindowCloseButton({
    super.key,
    required this.platform,
    required this.onPressed,
  });

  final TargetPlatform platform;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (platform != TargetPlatform.linux) {
      return DesktopIconButton(
        tooltip: '关闭',
        icon: const Icon(Icons.close, size: 17),
        onPressed: onPressed,
      );
    }
    return AppTooltip(
      message: '关闭',
      child: FocusableActionDetector(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onPressed();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          label: appText(context, '关闭'),
          onTap: onPressed,
          excludeSemantics: true,
          child: adw.AdwWindowButton(
            buttonType: adw.WindowButtonType.close,
            nativeControls: false,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
