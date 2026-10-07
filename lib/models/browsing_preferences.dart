class BrowsingPreferences {
  const BrowsingPreferences({
    this.view = 'list',
    this.listIconSize = 22,
    this.gridIconSize = 64,
    this.columnIconSize = 20,
    this.galleryIconSize = 80,
    this.inspector = true,
    this.sidebarWidth = 230,
    this.inspectorWidth = 270,
  });

  final String view;
  final double listIconSize, gridIconSize, columnIconSize, galleryIconSize;
  final double sidebarWidth, inspectorWidth;
  final bool inspector;

  double get iconSize => switch (view) {
    'grid' => gridIconSize,
    'columns' => columnIconSize,
    'gallery' => galleryIconSize,
    _ => listIconSize,
  };

  static double minIconSize(String view) =>
      ['grid', 'gallery'].contains(view) ? 32 : 12;
  static double maxIconSize(String view) => switch (view) {
    'grid' => 256,
    'gallery' => 160,
    'columns' => 32,
    _ => 36,
  };

  Map<String, dynamic> toJson() => {
    'view': view,
    'listIconSize': listIconSize,
    'gridIconSize': gridIconSize,
    'columnIconSize': columnIconSize,
    'galleryIconSize': galleryIconSize,
    'inspector': inspector,
    'sidebarWidth': sidebarWidth,
    'inspectorWidth': inspectorWidth,
  };

  factory BrowsingPreferences.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite && value >= min && value <= max
          ? value.toDouble()
          : fallback;
    }

    final view = ['list', 'grid', 'columns', 'gallery'].contains(json['view'])
        ? json['view'] as String
        : 'list';
    double size(String key, String mode, double fallback) {
      final legacy = json['iconSize'];
      if (!json.containsKey(key) &&
          view == mode &&
          legacy is num &&
          legacy.isFinite &&
          legacy >= 16 &&
          legacy <= 88) {
        // Older versions stored one slider value for every view.
        return legacy.toDouble().clamp(minIconSize(mode), maxIconSize(mode));
      }
      return number(key, fallback, minIconSize(mode), maxIconSize(mode));
    }

    return BrowsingPreferences(
      view: view,
      listIconSize: size('listIconSize', 'list', 22),
      gridIconSize: size('gridIconSize', 'grid', 64),
      columnIconSize: size('columnIconSize', 'columns', 20),
      galleryIconSize: size('galleryIconSize', 'gallery', 80),
      inspector: json['inspector'] is bool ? json['inspector'] as bool : true,
      sidebarWidth: number('sidebarWidth', 230, 160, 10000),
      inspectorWidth: number('inspectorWidth', 270, 220, 10000),
    );
  }
}
