class WebDavBackupFile {
  const WebDavBackupFile({
    required this.name,
    required this.path,
    this.updatedAt,
    this.size,
  });

  final String name;
  final String path;
  final DateTime? updatedAt;
  final int? size;
}
