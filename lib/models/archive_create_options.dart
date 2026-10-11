/// Per-operation options. Passwords are never persisted in application settings.
class ArchiveCreateOptions {
  const ArchiveCreateOptions({
    this.password = '',
    this.encryption = 'none',
    this.zipCompression = 'deflate',
    this.compressionLevel = 6,
    this.volumeSize = 0,
    this.comment = '',
    this.format = 'zip',
    this.nestInFolder = false,
    this.overwrite = true,
  });
  final String password, encryption, zipCompression;
  final int compressionLevel, volumeSize;
  final String comment;
  final String format;
  final bool nestInFolder, overwrite;
  bool get encrypted => encryption != 'none';

  Map<String, dynamic> toJson() => {
    'password': password,
    'encryption': encryption,
    'zipCompression': zipCompression,
    'compressionLevel': compressionLevel,
    'volumeSize': volumeSize,
    'comment': comment,
    'format': format,
    'nestInFolder': nestInFolder,
    'overwrite': overwrite,
  };

  factory ArchiveCreateOptions.fromJson(Map<String, dynamic> data) =>
      ArchiveCreateOptions(
        password: data['password'] as String,
        encryption: data['encryption'] as String,
        zipCompression: data['zipCompression'] as String,
        compressionLevel: data['compressionLevel'] as int,
        volumeSize: data['volumeSize'] as int,
        comment: data['comment'] as String,
        format: data['format'] as String,
        nestInFolder: data['nestInFolder'] as bool,
        overwrite: data['overwrite'] as bool,
      );
}
