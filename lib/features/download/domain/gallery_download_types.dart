class CancelFlag {
  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  void cancel() {
    _isCanceled = true;
  }
}

class GalleryDownloadProgress {
  const GalleryDownloadProgress({
    required this.done,
    required this.total,
    required this.success,
    required this.skipped,
    required this.failed,
    required this.status,
    this.currentImageId,
    this.lockoutRemaining,
    this.assumptionBroken = false,
  });

  final int done;
  final int total;
  final int success;
  final int skipped;
  final int failed;
  final GalleryDownloadStatus status;
  final int? currentImageId;
  final Duration? lockoutRemaining;
  final bool assumptionBroken;
}

enum GalleryDownloadStatus {
  running,
  lockout,
  canceled,
  done,
}

class GalleryDownloadResult {
  const GalleryDownloadResult({
    required this.total,
    required this.success,
    required this.skipped,
    required this.failed,
    required this.assumptionBroken,
    required this.canceled,
  });

  final int total;
  final int success;
  final int skipped;
  final int failed;
  final bool assumptionBroken;
  final bool canceled;
}
