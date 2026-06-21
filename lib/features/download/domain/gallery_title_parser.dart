String galleryDownloadButtonLabel(String? title) {
  final count = galleryImageCountHint(title);
  return count == null ? '下载整包' : '下载整包 (${count}P)';
}

int? galleryImageCountHint(String? title) {
  if (title == null) {
    return null;
  }
  final match = RegExp(r'\((\d+)\s*P(?:[^)]*)\)', caseSensitive: false)
      .firstMatch(title);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}
