import 'package:file_selector/file_selector.dart' as selector;
import 'package:nativeapi/nativeapi.dart';
export 'package:file_selector/file_selector.dart'
    show XFile, XTypeGroup, FileSaveLocation;

Future<List<selector.XFile>> openFiles({
  List<selector.XTypeGroup> acceptedTypeGroups = const [],
}) => NativeDocuments.openFiles(acceptedTypeGroups: acceptedTypeGroups);

Future<selector.FileSaveLocation?> getSaveLocation({
  String? suggestedName,
  String? initialDirectory,
  List<selector.XTypeGroup> acceptedTypeGroups = const [],
}) => NativeDocuments.getSaveLocation(
  suggestedName: suggestedName,
  initialDirectory: initialDirectory,
  acceptedTypeGroups: acceptedTypeGroups,
);

Future<String?> getDirectoryPath({String? confirmButtonText}) =>
    NativeDocuments.getDirectoryPath(confirmButtonText: confirmButtonText);
