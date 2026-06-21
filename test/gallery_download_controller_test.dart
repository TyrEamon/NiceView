import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/features/download/data/download_manifest_store.dart';
import 'package:nice_view/features/download/data/gallery_download_repository.dart';
import 'package:nice_view/features/download/domain/gallery_download_types.dart';
import 'package:nice_view/features/download/presentation/gallery_download_controller.dart';
import 'package:nice_view/features/random_image/domain/gallery_detail.dart';
import 'package:nice_view/services/app_exceptions.dart';
import 'package:nice_view/services/rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start writes progress and final result into state', () async {
    final controller = GalleryDownloadController(
      repository: await _FakeRepository.create(
        run: ({required onProgress, required cancel}) async {
          onProgress(
            const GalleryDownloadProgress(
              done: 1,
              total: 2,
              success: 1,
              skipped: 0,
              failed: 0,
              status: GalleryDownloadStatus.running,
            ),
          );
          onProgress(
            const GalleryDownloadProgress(
              done: 2,
              total: 2,
              success: 2,
              skipped: 0,
              failed: 0,
              status: GalleryDownloadStatus.done,
            ),
          );
          return const GalleryDownloadResult(
            total: 2,
            success: 2,
            skipped: 0,
            failed: 0,
            assumptionBroken: false,
            canceled: false,
          );
        },
      ),
    );

    await controller.start(42, titleHint: 'Sample Gallery');

    expect(controller.state.galleryId, 42);
    expect(controller.state.title, 'Sample Gallery');
    expect(controller.state.isRunning, isFalse);
    expect(controller.state.progress?.done, 2);
    expect(controller.state.result?.success, 2);
    expect(controller.state.error, isNull);
  });

  test('unexpected repository errors become UI error state', () async {
    final controller = GalleryDownloadController(
      repository: await _FakeRepository.create(
        run: ({required onProgress, required cancel}) async {
          throw const NiceViewException('boom');
        },
      ),
    );

    await controller.start(42);

    expect(controller.state.isRunning, isFalse);
    expect(controller.state.result, isNull);
    expect(controller.state.error, 'boom');
  });

  test('cancel marks state canceled while repository winds down', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    late CancelFlag cancelFlag;
    final controller = GalleryDownloadController(
      repository: await _FakeRepository.create(
        run: ({required onProgress, required cancel}) async {
          cancelFlag = cancel;
          onProgress(
            const GalleryDownloadProgress(
              done: 1,
              total: 3,
              success: 1,
              skipped: 0,
              failed: 0,
              status: GalleryDownloadStatus.running,
            ),
          );
          started.complete();
          await finish.future;
          onProgress(
            const GalleryDownloadProgress(
              done: 1,
              total: 3,
              success: 1,
              skipped: 0,
              failed: 0,
              status: GalleryDownloadStatus.canceled,
            ),
          );
          return const GalleryDownloadResult(
            total: 3,
            success: 1,
            skipped: 0,
            failed: 0,
            assumptionBroken: false,
            canceled: true,
          );
        },
      ),
    );

    final download = controller.start(42);
    await started.future;
    controller.cancel();

    expect(cancelFlag.isCanceled, isTrue);
    expect(controller.state.isRunning, isFalse);
    expect(controller.state.progress?.status, GalleryDownloadStatus.canceled);
    expect(controller.state.result?.canceled, isTrue);

    finish.complete();
    await download;

    expect(controller.state.result?.canceled, isTrue);
    expect(controller.state.progress?.status, GalleryDownloadStatus.canceled);
  });
}

typedef _FakeDownloadRun = Future<GalleryDownloadResult> Function({
  required void Function(GalleryDownloadProgress progress) onProgress,
  required CancelFlag cancel,
});

class _FakeRepository extends GalleryDownloadRepository {
  _FakeRepository._({
    required DownloadManifestStore manifestStore,
    required _FakeDownloadRun run,
  })  : _run = run,
        super(
          loadGallery: (_) async => const GalleryDetail(
            id: 42,
            imageCount: 0,
            images: [],
          ),
          loadImage: (_) async => throw UnimplementedError(),
          saveImageBytes: (
            List<int> bytes,
            String fileName,
            String mimeType, {
            String? subDir,
          }) async => '',
          manifestStore: manifestStore,
          rateLimiterState: () => RateLimiterState.initial(
            const RateLimiterConfig(),
            updatedAt: DateTime(2026, 6, 22),
          ),
          refreshRateLimiter: () async {},
        );

  final _FakeDownloadRun _run;

  static Future<_FakeRepository> create({
    required _FakeDownloadRun run,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    return _FakeRepository._(
      manifestStore: DownloadManifestStore(preferences),
      run: run,
    );
  }

  @override
  Future<GalleryDownloadResult> downloadGallery(
    int galleryId, {
    required void Function(GalleryDownloadProgress progress) onProgress,
    required CancelFlag cancel,
  }) {
    return _run(onProgress: onProgress, cancel: cancel);
  }
}
