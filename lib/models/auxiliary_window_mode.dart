enum AuxiliaryWindowMode {
  inline,
  separate;

  static const _buildMode = String.fromEnvironment(
    'HIZIP_WINDOW_MODE',
    defaultValue: 'separate',
  );

  static AuxiliaryWindowMode get buildDefault =>
      _buildMode == 'inline' ? inline : separate;

  static AuxiliaryWindowMode fromName(String? value) => values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => buildDefault,
  );
}
