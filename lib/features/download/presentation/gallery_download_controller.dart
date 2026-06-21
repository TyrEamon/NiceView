import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exceptions.dart';
import '../data/gallery_download_repository.dart';
import '../domain/gallery_download_types.dart';

final galleryDownloadControllerProvider = StateNotifierProvider<
    GalleryDownloadController, GalleryDownloadUiState>((ref) {
  return GalleryDownloadController(
    repository: ref.watch(galleryDownloadRepositoryProvider),
  );
});

const _unset = Object();

class GalleryDownloadUiState {
  const GalleryDownloadUiState({
    this.galleryId,
    this.title,
    this.progress,
    this.isRunning = false,
    this.result,
    this.error,
  });

  factory GalleryDownloadUiState.initial() {
    return const GalleryDownloadUiState();
  }

  final int? galleryId;
  final String? title;
  final GalleryDownloadProgress? progress;
  final bool isRunning;
  final GalleryDownloadResult? result;
  final String? error;

  GalleryDownloadUiState copyWith({
    Object? galleryId = _unset,
    Object? title = _unset,
    Object? progress = _unset,
    bool? isRunning,
    Object? result = _unset,
    Object? error = _unset,
  }) {
    return GalleryDownloadUiState(
      galleryId: identical(galleryId, _unset) ? this.galleryId : galleryId as int?,
      title: identical(title, _unset) ? this.title : title as String?,
      progress: identical(progress, _unset)
          ? this.progress
          : progress as GalleryDownloadProgress?,
      isRunning: isRunning ?? this.isRunning,
      result: identical(result, _unset) ? this.result : result as GalleryDownloadResult?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class GalleryDownloadController extends StateNotifier<GalleryDownloadUiState> {
  GalleryDownloadController({required GalleryDownloadRepository repository})
      : _repository = repository,
        super(GalleryDownloadUiState.initial());

  final GalleryDownloadRepository _repository;
  CancelFlag? _cancelFlag;
  bool _operationActive = false;
  bool _cancelRequested = false;
  int _generation = 0;

  Future<void> start(int galleryId, {String? titleHint}) async {
    if (_operationActive) {
      return;
    }

    final generation = ++_generation;
    final cancel = CancelFlag();
    _cancelFlag = cancel;
    _operationActive = true;
    _cancelRequested = false;
    state = GalleryDownloadUiState(
      galleryId: galleryId,
      title: titleHint,
      isRunning: true,
    );

    try {
      final result = await _repository.downloadGallery(
        galleryId,
        onProgress: (progress) {
          if (!mounted || generation != _generation) {
            return;
          }
          if (_cancelRequested &&
              progress.status != GalleryDownloadStatus.canceled) {
            return;
          }
          state = state.copyWith(
            progress: progress,
            isRunning: _isActiveProgress(progress),
            result: null,
            error: null,
          );
        },
        cancel: cancel,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      final displayResult = _cancelRequested && !result.canceled
          ? _canceledResultFromState()
          : result;
      state = state.copyWith(
        progress: state.progress ?? _progressFromResult(displayResult),
        isRunning: false,
        result: displayResult,
        error: null,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        isRunning: false,
        result: null,
        error: _messageForError(error),
      );
    } finally {
      if (generation == _generation) {
        _operationActive = false;
        _cancelFlag = null;
        _cancelRequested = false;
      }
    }
  }

  void cancel() {
    final cancel = _cancelFlag;
    if (cancel == null || cancel.isCanceled) {
      return;
    }
    cancel.cancel();
    _cancelRequested = true;

    final previous = state.progress;
    final canceledProgress = GalleryDownloadProgress(
      done: previous?.done ?? 0,
      total: previous?.total ?? 0,
      success: previous?.success ?? 0,
      skipped: previous?.skipped ?? 0,
      failed: previous?.failed ?? 0,
      status: GalleryDownloadStatus.canceled,
      currentImageId: previous?.currentImageId,
      assumptionBroken: previous?.assumptionBroken ?? false,
    );
    state = state.copyWith(
      progress: canceledProgress,
      isRunning: false,
      result: _resultFromProgress(canceledProgress, canceled: true),
      error: null,
    );
  }

  Future<void> retryFailed() async {
    final galleryId = state.galleryId;
    if (galleryId == null || _operationActive) {
      return;
    }
    await start(galleryId, titleHint: state.title);
  }

  bool _isActiveProgress(GalleryDownloadProgress progress) {
    return progress.status == GalleryDownloadStatus.running ||
        progress.status == GalleryDownloadStatus.lockout;
  }

  GalleryDownloadProgress _progressFromResult(GalleryDownloadResult result) {
    return GalleryDownloadProgress(
      done: result.success + result.skipped + result.failed,
      total: result.total,
      success: result.success,
      skipped: result.skipped,
      failed: result.failed,
      status: result.canceled
          ? GalleryDownloadStatus.canceled
          : GalleryDownloadStatus.done,
      assumptionBroken: result.assumptionBroken,
    );
  }

  GalleryDownloadResult _canceledResultFromState() {
    final progress = state.progress;
    if (progress != null) {
      return _resultFromProgress(progress, canceled: true);
    }
    return const GalleryDownloadResult(
      total: 0,
      success: 0,
      skipped: 0,
      failed: 0,
      assumptionBroken: false,
      canceled: true,
    );
  }

  GalleryDownloadResult _resultFromProgress(
    GalleryDownloadProgress progress, {
    required bool canceled,
  }) {
    return GalleryDownloadResult(
      total: progress.total,
      success: progress.success,
      skipped: progress.skipped,
      failed: progress.failed,
      assumptionBroken: progress.assumptionBroken,
      canceled: canceled,
    );
  }

  String _messageForError(Object error) {
    if (error is NiceViewException) {
      return error.message;
    }
    return '下载失败，请稍后再试';
  }
}
