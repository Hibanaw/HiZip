import 'package:path/path.dart' as p;

/// One Finder selection, kept together even while other requests are queued.
class FinderCompressionRequest {
  const FinderCompressionRequest({required this.paths, this.quickZip = false});
  final List<String> paths;
  final bool quickZip;
  bool get defaultNestInFolder => !quickZip && paths.length > 1;

  factory FinderCompressionRequest.fromPlatform(Object? arguments) {
    if (arguments is! Map ||
        !['create', 'quickZip'].contains(arguments['action']) ||
        arguments['paths'] is! List) {
      throw const FormatException('Invalid Finder compression request');
    }
    final paths = arguments['paths'] as List;
    if (paths.isEmpty ||
        paths.any(
          (path) =>
              path is! String ||
              !(p.posix.isAbsolute(path) || p.windows.isAbsolute(path)) ||
              path.contains('\u0000'),
        )) {
      throw const FormatException('Invalid Finder selection');
    }
    // Explorer sends drive or UNC paths; Finder sends POSIX paths.
    String normalize(String path) => p.posix.isAbsolute(path)
        ? p.posix.normalize(path)
        : p.windows.normalize(path);
    return FinderCompressionRequest(
      paths: paths.cast<String>().map(normalize).toSet().toList(),
      quickZip: arguments['action'] == 'quickZip',
    );
  }
}
