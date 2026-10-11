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
    this.listSortColumn = 'name',
    this.listSortAscending = true,
    this.listNameWidth = 0,
    this.listSizeWidth = 85,
    this.listModifiedWidth = 115,
    this.listKindWidth = 85,
  });

  final String view;
  final double listIconSize, gridIconSize, columnIconSize, galleryIconSize;
  final double sidebarWidth, inspectorWidth;
  final bool inspector;
  final String listSortColumn;
  final bool listSortAscending;
  final double listNameWidth, listSizeWidth, listModifiedWidth, listKindWidth;

  double get iconSize => switch (view) {
    'grid' => gridIconSize,
    'columns' => columnIconSize,
    'gallery' => galleryIconSize,
    _ => listIconSize,
  };

  static double minIconSize(String view) =>
      ['grid', 'gallery'].contains(view) ? 32 : 12;
  static double maxIconSize(String view) => switch (view) {
    'grid' => 144,
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
    'listSortColumn': listSortColumn,
    'listSortAscending': listSortAscending,
    'listNameWidth': listNameWidth,
    'listSizeWidth': listSizeWidth,
    'listModifiedWidth': listModifiedWidth,
    'listKindWidth': listKindWidth,
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
      final value = json[key];
      if (mode == 'grid' &&
          value is num &&
          value.isFinite &&
          value > maxIconSize(mode) &&
          value <= 256) {
        // Preserve sizes from the previous grid range at the new maximum.
        return maxIconSize(mode);
      }
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
      listSortColumn:
          ['name', 'size', 'modified', 'kind'].contains(json['listSortColumn'])
          ? json['listSortColumn'] as String
          : 'name',
      listSortAscending: json['listSortAscending'] is bool
          ? json['listSortAscending'] as bool
          : true,
      listNameWidth: number('listNameWidth', 0, 0, 2000),
      listSizeWidth: number('listSizeWidth', 85, 65, 400),
      listModifiedWidth: number('listModifiedWidth', 115, 90, 400),
      listKindWidth: number('listKindWidth', 85, 65, 2000),
    );
  }
}
