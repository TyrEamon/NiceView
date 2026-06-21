import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/features/download/data/download_manifest_store.dart';
import 'package:nice_view/features/download/data/gallery_download_repository.dart';
import 'package:nice_view/features/download/domain/gallery_download_types.dart';
import 'package:nice_view/features/random_image/data/veil_api_client.dart';
import 'package:nice_view/features/random_image/domain/gallery_detail.dart';
import 'package:nice_view/services/app_exceptions.dart';
import 'package:nice_view/services/rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloads inferred full gallery sequentially', () async {
    final harness = await _Harness.create(
      gallery: _gallery(imageCount: 3),
    );

    final progress = <GalleryDownloadProgress>[];
    final result = await harness.repository.downloadGallery(
      42,
      onProgress: progress.add,
      cancel: CancelFlag(),
    );

    expect(result.total, 3);
    expect(result.success, 3);
    expect(result.skipped, 0);
    expect(result.failed, 0);
    expect(result.assumptionBroken, isFalse);
    expect(result.canceled, isFalse);
    expect(harness.requestedImages, [100, 101, 102]);
    expect(harness.savedFileNames, ['001_100.jpg', '002_101.jpg', '003_102.jpg']);
    expect(harness.savedSubDirs.toSet(), {'Sample Gallery'});
    expect(harness.manifest.downloadedImageIds(42), {100, 101, 102});
    expect(progress.last.status, GalleryDownloadStatus.done);
    expect(progress.last.done, 3);
  });

  test('skips manifest entries for resume', () async {
    final harness = await _Harness.create(
      gallery: _gallery(imageCount: 3),
      downloaded: {101},
    );

    final result = await harness.repository.downloadGallery(
      42,
      onProgress: (_) {},
      cancel: CancelFlag(),
    );

    expect(result.success, 2);
    expect(result.skipped, 1);
    expect(harness.requestedImages, [100, 102]);
    expect(harness.savedFileNames, ['001_100.jpg', '003_102.jpg']);
  });

  test('skips 404 images without failing gallery', () async {
    final harness = await _Harness.create(
      gallery: _gallery(imageCount: 3),
      imageErrors: {101: const ImageNotFoundException('missing')},
    );

    final result = await harness.repository.downloadGallery(
      42,
      onProgress: (_) {},
      cancel: CancelFlag(),
    );

    expect(result.success, 2);
    expect(result.skipped, 1);
    expect(result.failed, 0);
    expect(harness.manifest.downloadedImageIds(42), {100, 102});
  });

  test('cancels before the next image', () async {
    final harness = await _Harness.create(
      gallery: _gallery(imageCount: 3),
    );
    final cancel = CancelFlag();

    final result = await harness.repository.downloadGallery(
      42,
      onProgress: (progress) {
        if (progress.success == 1) {
          cancel.cancel();
        }
      },
      cancel: cancel,
    );

    expect(result.canceled, isTrue);
    expect(result.success, 1);
    expect(result.total, 3);
    expect(harness.requestedImages, [100]);
  });

  test('waits through lockout then retries current image', () async {
    final lockoutUntil = DateTime(2026, 6, 22, 10, 0, 2);
    var now = DateTime(2026, 6, 22, 10);
    final harness = await _Harness.create(
      gallery: _gallery(imageCount: 1),
      imageErrors: {100: const ServerLockoutException('locked')},
      now: () => now,
      sleep: (duration) async {
        now = now.add(duration);
      },
    );
    harness.lockoutUntil = lockoutUntil;

    final lockoutProgress = <GalleryDownloadProgress>[];
    final result = await harness.repository.downloadGallery(
      42,
      onProgress: (progress) {
        if (progress.status == GalleryDownloadStatus.lockout) {
          lockoutProgress.add(progress);
        }
      },
      cancel: CancelFlag(),
    );

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(harness.requestedImages, [100, 100]);
    expect(lockoutProgress, isNotEmpty);
    expect(lockoutProgress.first.lockoutRemaining, const Duration(seconds: 2));
  });

  test('falls back to first page when continuity assumption breaks', () async {
    final harness = await _Harness.create(
      gallery: const GalleryDetail(
        id: 42,
        title: 'Broken Gallery',
        imageCount: 5,
        coverImageId: 100,
        images: [
          GalleryImageRef(id: 100, sortOrder: 1),
          GalleryImageRef(id: 103, sortOrder: 2),
        ],
      ),
    );

    final result = await harness.repository.downloadGallery(
      42,
      onProgress: (_) {},
      cancel: CancelFlag(),
    );

    expect(result.assumptionBroken, isTrue);
    expect(result.total, 2);
    expect(result.success, 2);
    expect(harness.requestedImages, [100, 103]);
  });
}

GalleryDetail _gallery({required int imageCount}) {
  return GalleryDetail(
    id: 42,
    title: 'Sample Gallery',
    category: 'Cosplay',
    imageCount: imageCount,
    coverImageId: 100,
    images: List<GalleryImageRef>.generate(
      imageCount.clamp(0, 3).toInt(),
      (index) => GalleryImageRef(
        id: 100 + index,
        sortOrder: index + 1,
        width: 1200,
        height: 800,
        orientation: 'landscape',
      ),
    ),
  );
}

class _Harness {
  _Harness._({
    required this.repository,
    required this.manifest,
    required this.requestedImages,
    required this.savedFileNames,
    required this.savedSubDirs,
    required this.imageErrors,
  });

  final GalleryDownloadRepository repository;
  final DownloadManifestStore manifest;
  final List<int> requestedImages;
  final List<String> savedFileNames;
  final List<String?> savedSubDirs;
  final Map<int, Object> imageErrors;
  DateTime? lockoutUntil;

  static Future<_Harness> create({
    required GalleryDetail gallery,
    Set<int> downloaded = const {},
    Map<int, Object> imageErrors = const {},
    DateTime Function()? now,
    Future<void> Function(Duration duration)? sleep,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final manifest = DownloadManifestStore(preferences);
    for (final imageId in downloaded) {
      await manifest.markDownloaded(42, imageId);
    }

    final requestedImages = <int>[];
    final savedFileNames = <String>[];
    final savedSubDirs = <String?>[];
    final remainingErrors = Map<int, Object>.from(imageErrors);
    late final _Harness harness;
    var state = RateLimiterState.initial(
      const RateLimiterConfig(),
      updatedAt: (now ?? DateTime.now)(),
    );

    harness = _Harness._(
      repository: GalleryDownloadRepository(
        loadGallery: (_) async => gallery,
        loadImage: (imageId) async {
          requestedImages.add(imageId);
          final error = remainingErrors[imageId];
          if (error != null) {
            remainingErrors.remove(imageId);
            throw error;
          }
          return VeilImageResponse(
            bytes: [imageId],
            contentType: 'image/jpeg',
            imageId: imageId,
            galleryId: 42,
          );
        },
        saveImageBytes: (
          bytes,
          fileName,
          mimeType, {
          String? subDir,
        }) async {
          savedFileNames.add(fileName);
          savedSubDirs.add(subDir);
          return 'saved/$fileName';
        },
        manifestStore: manifest,
        rateLimiterState: () => state,
        refreshRateLimiter: () async {
          final current = (now ?? DateTime.now)();
          state = state.copyWith(
            updatedAt: current,
            lockoutUntil: harness.lockoutUntil != null &&
                    current.isBefore(harness.lockoutUntil!)
                ? harness.lockoutUntil
                : null,
          );
        },
        delay: sleep,
      ),
      manifest: manifest,
      requestedImages: requestedImages,
      savedFileNames: savedFileNames,
      savedSubDirs: savedSubDirs,
      imageErrors: remainingErrors,
    );
    return harness;
  }
}
