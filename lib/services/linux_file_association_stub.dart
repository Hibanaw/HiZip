Future<int> setDefaultArchiveHandler() =>
    Future.error(UnsupportedError('Linux 文件关联仅支持 Linux 桌面端'));

Future<List<String>> initialArchivePaths() async => const [];
