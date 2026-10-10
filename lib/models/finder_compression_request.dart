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
              !p.posix.isAbsolute(path) ||
              path.contains('\u0000'),
        )) {
      throw const FormatException('Invalid Finder selection');
    }
    return FinderCompressionRequest(
      paths: paths.cast<String>().map(p.normalize).toSet().toList(),
      quickZip: arguments['action'] == 'quickZip',
    );
  }
}
