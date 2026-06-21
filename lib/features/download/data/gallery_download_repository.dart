import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exceptions.dart';
import '../../../services/download_service.dart';
import '../../../services/rate_limiter.dart';
import '../../random_image/data/random_image_repository.dart';
import '../../random_image/data/veil_api_client.dart';
import '../../random_image/domain/gallery_detail.dart';
import '../domain/gallery_download_types.dart';
import 'download_manifest_store.dart';

final galleryDownloadRepositoryProvider = Provider<GalleryDownloadRepository>((
  ref,
) {
  final api = ref.watch(veilApiClientProvider);
  final downloadService = ref.watch(downloadServiceProvider);
  final rateLimiter = ref.watch(rateLimiterProvider.notifier);
  return GalleryDownloadRepository(
    loadGallery: api.gallery,
    loadImage: api.imageById,
    saveImageBytes: downloadService.saveImageBytes,
    manifestStore: ref.watch(downloadManifestStoreProvider),
    rateLimiterState: () => rateLimiter.state,
    refreshRateLimiter: rateLimiter.refresh,
  );
});

typedef GalleryLoader = Future<GalleryDetail> Function(int galleryId);
typedef ImageLoader = Future<VeilImageResponse> Function(int imageId);
typedef ImageBytesSaver = Future<String> Function(
  List<int> bytes,
  String fileName,
  String mimeType, {
  String? subDir,
});
typedef AsyncDelay = Future<void> Function(Duration duration);
typedef RateLimiterStateReader = RateLimiterState Function();
typedef RateLimiterRefresher = Future<void> Function();

class GalleryDownloadRepository {
  GalleryDownloadRepository({
    required GalleryLoader loadGallery,
    required ImageLoader loadImage,
    required ImageBytesSaver saveImageBytes,
    required DownloadManifestStore manifestStore,
    required RateLimiterStateReader rateLimiterState,
    required RateLimiterRefresher refreshRateLimiter,
    AsyncDelay? delay,
  })  : _loadGallery = loadGallery,
        _loadImage = loadImage,
        _saveImageBytes = saveImageBytes,
        _manifestStore = manifestStore,
        _rateLimiterState = rateLimiterState,
        _refreshRateLimiter = refreshRateLimiter,
        _delay = delay ?? Future<void>.delayed;

  static const _maxRetries = 2;

  final GalleryLoader _loadGallery;
  final ImageLoader _loadImage;
  final ImageBytesSaver _saveImageBytes;
  final DownloadManifestStore _manifestStore;
  final RateLimiterStateReader _rateLimiterState;
  final RateLimiterRefresher _refreshRateLimiter;
  final AsyncDelay _delay;

  Future<GalleryDownloadResult> downloadGallery(
    int galleryId, {
    required void Function(GalleryDownloadProgress progress) onProgress,
    required CancelFlag cancel,
  }) async {
    final gallery = await _loadGallery(galleryId);
    final plan = _buildPlan(gallery);
    final total = plan.items.length;
    final subDir = sanitizeFileName(
      gallery.title?.trim().isNotEmpty == true
          ? gallery.title!
          : 'gallery_$galleryId',
    );
    var success = 0;
    var skipped = 0;
    var failed = 0;

    void emit(
      GalleryDownloadStatus status, {
      int? currentImageId,
      Duration? lockoutRemaining,
    }) {
      onProgress(
        GalleryDownloadProgress(
          done: success + skipped + failed,
          total: total,
          success: success,
          skipped: skipped,
          failed: failed,
          status: status,
          currentImageId: currentImageId,
          lockoutRemaining: lockoutRemaining,
          assumptionBroken: plan.assumptionBroken,
        ),
      );
    }

    emit(GalleryDownloadStatus.running);
    for (final item in plan.items) {
      if (cancel.isCanceled) {
        emit(GalleryDownloadStatus.canceled, currentImageId: item.imageId);
        return GalleryDownloadResult(
          total: total,
          success: success,
          skipped: skipped,
          failed: failed,
          assumptionBroken: plan.assumptionBroken,
          canceled: true,
        );
      }

      final downloaded = _manifestStore.downloadedImageIds(galleryId);
      if (downloaded.contains(item.imageId)) {
        skipped += 1;
        emit(GalleryDownloadStatus.running, currentImageId: item.imageId);
        continue;
      }

      final outcome = await _downloadOne(
        galleryId: galleryId,
        item: item,
        subDir: subDir,
        cancel: cancel,
        onLockout: (remaining) {
          emit(
            GalleryDownloadStatus.lockout,
            currentImageId: item.imageId,
            lockoutRemaining: remaining,
          );
        },
      );

      if (outcome == _ImageOutcome.canceled) {
        emit(GalleryDownloadStatus.canceled, currentImageId: item.imageId);
        return GalleryDownloadResult(
          total: total,
          success: success,
          skipped: skipped,
          failed: failed,
          assumptionBroken: plan.assumptionBroken,
          canceled: true,
        );
      }
      if (outcome == _ImageOutcome.success) {
        success += 1;
      } else if (outcome == _ImageOutcome.skipped) {
        skipped += 1;
      } else {
        failed += 1;
      }
      emit(GalleryDownloadStatus.running, currentImageId: item.imageId);
    }

    emit(GalleryDownloadStatus.done);
    return GalleryDownloadResult(
      total: total,
      success: success,
      skipped: skipped,
      failed: failed,
      assumptionBroken: plan.assumptionBroken,
      canceled: false,
    );
  }

  _DownloadPlan _buildPlan(GalleryDetail gallery) {
    final coverImageId = gallery.coverImageId;
    final firstPage = gallery.images;
    final assumptionHolds = coverImageId != null &&
        firstPage.isNotEmpty &&
        firstPage.every((image) {
          final sortOrder = image.sortOrder;
          return sortOrder != null && image.id == coverImageId + sortOrder - 1;
        });

    if (!assumptionHolds) {
      return _DownloadPlan(
        items: List<_DownloadItem>.generate(firstPage.length, (index) {
          final image = firstPage[index];
          return _DownloadItem(
            imageId: image.id,
            sortOrder: image.sortOrder ?? index + 1,
          );
        }),
        assumptionBroken: true,
      );
    }

    return _DownloadPlan(
      items: List<_DownloadItem>.generate(gallery.imageCount, (index) {
        final imageId = coverImageId + index;
        return _DownloadItem(imageId: imageId, sortOrder: index + 1);
      }),
      assumptionBroken: false,
    );
  }

  Future<_ImageOutcome> _downloadOne({
    required int galleryId,
    required _DownloadItem item,
    required String subDir,
    required CancelFlag cancel,
    required void Function(Duration remaining) onLockout,
  }) async {
    var attempt = 0;
    while (true) {
      if (cancel.isCanceled) {
        return _ImageOutcome.canceled;
      }
      try {
        final response = await _loadImage(item.imageId);
        if (response.galleryId != null && response.galleryId != galleryId) {
          return _ImageOutcome.skipped;
        }
        final mimeType = response.contentType?.split(';').first.trim() ??
            'image/jpeg';
        await _saveImageBytes(
          response.bytes,
          _fileNameFor(item, mimeType),
          mimeType,
          subDir: subDir,
        );
        await _manifestStore.markDownloaded(galleryId, item.imageId);
        return _ImageOutcome.success;
      } on ServerLockoutException {
        final canceled = await _waitForLockout(cancel, onLockout);
        if (canceled) {
          return _ImageOutcome.canceled;
        }
      } on ImageNotFoundException {
        return _ImageOutcome.skipped;
      } catch (_) {
        if (attempt >= _maxRetries) {
          return _ImageOutcome.failed;
        }
        attempt += 1;
        await _delay(Duration(seconds: attempt));
      }
    }
  }

  Future<bool> _waitForLockout(
    CancelFlag cancel,
    void Function(Duration remaining) onLockout,
  ) async {
    while (true) {
      if (cancel.isCanceled) {
        return true;
      }
      await _refreshRateLimiter();
      final remaining = _rateLimiterState().lockoutRemaining;
      if (remaining <= Duration.zero) {
        return false;
      }
      onLockout(remaining);
      await _delay(const Duration(seconds: 1));
    }
  }

  String _fileNameFor(_DownloadItem item, String mimeType) {
    final order = item.sortOrder?.toString().padLeft(3, '0') ?? '000';
    return '${order}_${item.imageId}${extensionForContentType(mimeType)}';
  }
}

class _DownloadPlan {
  const _DownloadPlan({
    required this.items,
    required this.assumptionBroken,
  });

  final List<_DownloadItem> items;
  final bool assumptionBroken;
}

class _DownloadItem {
  const _DownloadItem({
    required this.imageId,
    required this.sortOrder,
  });

  final int imageId;
  final int? sortOrder;
}

enum _ImageOutcome {
  success,
  skipped,
  failed,
  canceled,
}
