class TaskFeedback {
  const TaskFeedback({
    required this.title,
    this.detail = '',
    this.running = false,
    this.error = false,
    this.progress,
    this.fileProgress,
    this.currentFile = '',
    this.actions = const {'dismiss': '关闭'},
  });
  final String title, detail;
  final bool running, error;
  final double? progress;
  final double? fileProgress;
  final String currentFile;
  final Map<String, String> actions;
  Map<String, dynamic> toJson() => {
    'title': title,
    'detail': detail,
    'running': running,
    'error': error,
    'progress': progress,
    'fileProgress': fileProgress,
    'currentFile': currentFile,
    'actions': actions,
  };
  factory TaskFeedback.fromJson(Map<String, dynamic> json) => TaskFeedback(
    title: json['title'] as String,
    detail: json['detail'] as String? ?? '',
    running: json['running'] as bool? ?? false,
    error: json['error'] as bool? ?? false,
    progress: (json['progress'] as num?)?.toDouble(),
    fileProgress: (json['fileProgress'] as num?)?.toDouble(),
    currentFile: json['currentFile'] as String? ?? '',
    actions: Map<String, String>.from(json['actions'] as Map? ?? const {}),
  );
}
