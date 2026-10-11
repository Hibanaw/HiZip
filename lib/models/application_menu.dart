/// One menu definition is used by the native menu bar and the in-app menu.
class ApplicationMenuItem {
  const ApplicationMenuItem(
    this.title, {
    this.command,
    this.children,
    this.enabled = true,
    this.checked = false,
    this.key = '',
    this.modifiers = const ['command'],
  }) : separator = false;

  const ApplicationMenuItem.separator()
    : title = '',
      command = null,
      children = null,
      enabled = false,
      checked = false,
      key = '',
      modifiers = const [],
      separator = true;

  final String title, key;
  final String? command;
  final List<ApplicationMenuItem>? children;
  final bool enabled, checked, separator;
  final List<String> modifiers;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (command != null) 'command': command,
    if (children != null)
      'children': children!.map((item) => item.toJson()).toList(),
    'enabled': enabled,
    'checked': checked,
    'separator': separator,
    'key': key,
    'modifiers': modifiers,
  };
}
