const archiveEncodings = <String, String>{
  'auto': '自动识别',
  'UTF-8': 'UTF-8',
  'GB18030': '简体中文（GB18030 / GBK）',
  'BIG5': '繁体中文（Big5）',
  'CP932': '日文（Shift-JIS）',
  'CP949': '韩文（CP949）',
  'CP437': 'DOS（CP437）',
  'WINDOWS-1252': '西欧（Windows-1252）',
};

class ArchivePreferences {
  const ArchivePreferences({
    this.readEncoding = 'auto',
    this.createEncoding = 'UTF-8',
    this.compressionLevel = 6,
  });
  final String readEncoding, createEncoding;
  final int compressionLevel;
  Map<String, dynamic> toJson() => {
    'readEncoding': readEncoding,
    'createEncoding': createEncoding,
    'compressionLevel': compressionLevel,
  };
  factory ArchivePreferences.fromJson(Map<String, dynamic> json) =>
      ArchivePreferences(
        readEncoding: archiveEncodings.containsKey(json['readEncoding'])
            ? json['readEncoding'] as String
            : 'auto',
        createEncoding:
            json['createEncoding'] != 'auto' &&
                archiveEncodings.containsKey(json['createEncoding'])
            ? json['createEncoding'] as String
            : 'UTF-8',
        compressionLevel:
            json['compressionLevel'] is int &&
                json['compressionLevel'] >= 0 &&
                json['compressionLevel'] <= 9
            ? json['compressionLevel'] as int
            : 6,
      );
}
