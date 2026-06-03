import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exceptions.dart';
import '../../../services/download_service.dart';
import '../../../services/quota_service.dart';
import '../../tags/data/local_tag_store.dart';
import '../data/favorite_store.dart';
import '../data/history_store.dart';
import '../data/random_image_repository.dart';
import '../domain/favorite_image.dart';
import '../domain/history_image.dart';
import '../domain/image_metadata.dart';
import '../domain/quota_state.dart';
import '../domain/random_image.dart';

final randomImageControllerProvider =
    StateNotifierProvider<RandomImageController, RandomImageViewState>((ref) {
  final controller = RandomImageController(
    repository: ref.watch(randomImageRepositoryProvider),
    tagStore: ref.watch(localTagStoreProvider),
    favoriteStore: ref.watch(favoriteStoreProvider),
    historyStore: ref.watch(historyStoreProvider),
    downloadService: ref.watch(downloadServiceProvider),
    quotaController: ref.read(quotaControllerProvider.notifier),
    readQuotaState: () => ref.read(quotaControllerProvider),
  );
  unawaited(controller.initialize());
  return controller;
});

const _unset = Object();
const _defaultPreloadTarget = 6;
const _adjacentPreloadTarget = 4;
const _recentLocalImageLimit = 48;

class RandomImageViewState {
  const RandomImageViewState({
    required this.preloadQueue,
    required this.historyImages,
    required this.favoriteImages,
    required this.preloadTarget,
    required this.isFastBrowseMode,
    required this.consecutivePreloadExhaustions,
    required this.isImageZoomed,
    required this.userTags,
    required this.isInitialLoading,
    required this.isPreloading,
    required this.isNextLoading,
    required this.isDownloading,
    required this.isMetadataLoading,
    this.currentImage,
    this.currentMetadata,
    this.adjacentLoadingDelta,
    this.favoriteLoadingImageId,
    this.previousAdjacentQueue = const [],
    this.nextAdjacentQueue = const [],
    this.selectedTag,
    this.errorMessage,
    this.lastLoadError,
  });

  factory RandomImageViewState.initial() {
    return const RandomImageViewState(
      preloadQueue: [],
      historyImages: [],
      favoriteImages: [],
      preloadTarget: _defaultPreloadTarget,
      isFastBrowseMode: false,
      consecutivePreloadExhaustions: 0,
      isImageZoomed: false,
      userTags: [],
      isInitialLoading: true,
      isPreloading: false,
      isNextLoading: false,
      isDownloading: false,
      isMetadataLoading: false,
    );
  }

  final RandomImage? currentImage;
  final ImageMetadata? currentMetadata;
  final int? adjacentLoadingDelta;
  final int? favoriteLoadingImageId;
  final List<RandomImage> previousAdjacentQueue;
  final List<RandomImage> nextAdjacentQueue;
  final List<RandomImage> preloadQueue;
  final List<HistoryImage> historyImages;
  final List<FavoriteImage> favoriteImages;
  final int preloadTarget;
  final bool isFastBrowseMode;
  final int consecutivePreloadExhaustions;
  final bool isImageZoomed;
  final String? selectedTag;
  final List<String> userTags;
  final bool isInitialLoading;
  final bool isPreloading;
  final bool isNextLoading;
  final bool isDownloading;
  final bool isMetadataLoading;
  final String? errorMessage;
  final String? lastLoadError;

  RandomImageViewState copyWith({
    Object? currentImage = _unset,
    Object? currentMetadata = _unset,
    Object? adjacentLoadingDelta = _unset,
    Object? favoriteLoadingImageId = _unset,
    List<RandomImage>? previousAdjacentQueue,
    List<RandomImage>? nextAdjacentQueue,
    List<RandomImage>? preloadQueue,
    List<HistoryImage>? historyImages,
    List<FavoriteImage>? favoriteImages,
    int? preloadTarget,
    bool? isFastBrowseMode,
    int? consecutivePreloadExhaustions,
    bool? isImageZoomed,
    Object? selectedTag = _unset,
    List<String>? userTags,
    bool? isInitialLoading,
    bool? isPreloading,
    bool? isNextLoading,
    bool? isDownloading,
    bool? isMetadataLoading,
    Object? errorMessage = _unset,
    Object? lastLoadError = _unset,
  }) {
    return RandomImageViewState(
      currentImage: identical(currentImage, _unset)
          ? this.currentImage
          : currentImage as RandomImage?,
      currentMetadata: identical(currentMetadata, _unset)
          ? this.currentMetadata
          : currentMetadata as ImageMetadata?,
      adjacentLoadingDelta: identical(adjacentLoadingDelta, _unset)
          ? this.adjacentLoadingDelta
          : adjacentLoadingDelta as int?,
      favoriteLoadingImageId: identical(favoriteLoadingImageId, _unset)
          ? this.favoriteLoadingImageId
          : favoriteLoadingImageId as int?,
      previousAdjacentQueue:
          previousAdjacentQueue ?? this.previousAdjacentQueue,
      nextAdjacentQueue: nextAdjacentQueue ?? this.nextAdjacentQueue,
      preloadQueue: preloadQueue ?? this.preloadQueue,
      historyImages: historyImages ?? this.historyImages,
      favoriteImages: favoriteImages ?? this.favoriteImages,
      preloadTarget: preloadTarget ?? this.preloadTarget,
      isFastBrowseMode: isFastBrowseMode ?? this.isFastBrowseMode,
      consecutivePreloadExhaustions:
          consecutivePreloadExhaustions ?? this.consecutivePreloadExhaustions,
      isImageZoomed: isImageZoomed ?? this.isImageZoomed,
      selectedTag: identical(selectedTag, _unset)
          ? this.selectedTag
          : selectedTag as String?,
      userTags: userTags ?? this.userTags,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isPreloading: isPreloading ?? this.isPreloading,
      isNextLoading: isNextLoading ?? this.isNextLoading,
      isDownloading: isDownloading ?? this.isDownloading,
      isMetadataLoading: isMetadataLoading ?? this.isMetadataLoading,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      lastLoadError: identical(lastLoadError, _unset)
          ? this.lastLoadError
          : lastLoadError as String?,
    );
  }
}

class RandomImageController extends StateNotifier<RandomImageViewState> {
  RandomImageController({
    required RandomImageRepository repository,
    required LocalTagStore tagStore,
    required FavoriteStore favoriteStore,
    required HistoryStore historyStore,
    required DownloadService downloadService,
    required QuotaController quotaController,
    required QuotaState Function() readQuotaState,
  })  : _repository = repository,
        _tagStore = tagStore,
        _favoriteStore = favoriteStore,
        _historyStore = historyStore,
        _downloadService = downloadService,
        _quotaController = quotaController,
        _readQuotaState = readQuotaState,
        super(RandomImageViewState.initial());

  final RandomImageRepository _repository;
  final LocalTagStore _tagStore;
  final FavoriteStore _favoriteStore;
  final HistoryStore _historyStore;
  final DownloadService _downloadService;
  final QuotaController _quotaController;
  final QuotaState Function() _readQuotaState;
  final ListQueue<int> _recentImageIds = ListQueue<int>();
  final Map<int, RandomImage> _recentLocalImagesById = <int, RandomImage>{};
  final Set<String> _pendingConsumedPreloadPaths = <String>{};

  bool _initialized = false;
  bool _isPreloading = false;
  bool _isPreloadingAdjacent = false;
  int _generation = 0;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _log('initialize');

    final tags = _tagStore.loadTags();
    final selectedTag = _tagStore.loadSelectedTag();
    final effectiveSelectedTag =
        selectedTag != null && tags.contains(selectedTag) ? selectedTag : null;
    if (effectiveSelectedTag != selectedTag) {
      await _tagStore.saveSelectedTag(effectiveSelectedTag);
    }

    var historyImages = await _historyStore.load();
    final favoriteImages = await _favoriteStore.load();
    var restoredImage = await _restoreLastCurrent(historyImages);
    var preloadQueue = await _historyStore.loadPreloadQueue(
      selectedTag: effectiveSelectedTag,
    );
    if (restoredImage == null && preloadQueue.isNotEmpty) {
      restoredImage = preloadQueue.first;
      preloadQueue = preloadQueue.skip(1).toList();
      historyImages = await _historyStore.upsertFromRandomImage(restoredImage);
      if (historyImages.isNotEmpty) {
        restoredImage = _randomImageFromHistory(historyImages.first);
      }
      preloadQueue = await _historyStore.savePreloadQueue(
        preloadQueue,
        selectedTag: effectiveSelectedTag,
      );
    } else if (restoredImage != null) {
      preloadQueue = preloadQueue
          .where((image) => !_isSameImage(image, restoredImage!))
          .toList();
      preloadQueue = await _historyStore.savePreloadQueue(
        preloadQueue,
        selectedTag: effectiveSelectedTag,
      );
    }
    if (!mounted) {
      return;
    }
    if (restoredImage != null) {
      _rememberImageId(restoredImage.imageId);
      _rememberLocalImage(restoredImage);
    }
    for (final image in preloadQueue) {
      _rememberImageId(image.imageId);
      _rememberLocalImage(image);
    }
    state = state.copyWith(
      currentImage: restoredImage,
      preloadQueue: preloadQueue,
      favoriteImages: favoriteImages,
      userTags: tags,
      selectedTag: effectiveSelectedTag,
      historyImages: historyImages,
      preloadTarget: _defaultPreloadTarget,
      isInitialLoading: restoredImage == null,
    );

    if (restoredImage == null) {
      await _loadFreshCurrent(isInitial: true);
    } else {
      unawaited(_fillPreloadQueue(_generation));
    }
  }

  void setImageZoomed(bool value) {
    if (state.isImageZoomed == value) {
      return;
    }
    state = state.copyWith(isImageZoomed: value);
  }

  Future<void> nextImage() async {
    if (state.isInitialLoading || state.isNextLoading) {
      return;
    }
    if (_readQuotaState().isServerLocked) {
      state = state.copyWith(errorMessage: '歇 60 秒，让服务器也喝口水。');
      return;
    }

    state = state.copyWith(errorMessage: null);
    if (state.preloadQueue.isNotEmpty) {
      final queue = [...state.preloadQueue];
      final next = queue.removeAt(0);
      final browsing = _nextBrowseMode(queue.isEmpty);
      final generation = _generation;
      final selectedTag = state.selectedTag;
      _pendingConsumedPreloadPaths.add(next.localFilePath);
      _rememberImageId(next.imageId);
      _rememberLocalImage(next);
      state = state.copyWith(
        currentImage: next,
        currentMetadata: null,
        adjacentLoadingDelta: null,
        previousAdjacentQueue: const [],
        nextAdjacentQueue: const [],
        preloadQueue: queue,
        isImageZoomed: false,
        isMetadataLoading: false,
        consecutivePreloadExhaustions: browsing.exhaustions,
        isFastBrowseMode: browsing.isFast,
        preloadTarget: browsing.target,
      );
      unawaited(_persistConsumedPreloadedImage(
        next,
        generation: generation,
        selectedTag: selectedTag,
      ));
      unawaited(_fillPreloadQueue(_generation));
      return;
    }

    if (!_readQuotaState().canAcquire) {
      state = state.copyWith(errorMessage: _quotaRecoveryMessage());
      return;
    }

    final browsing = _nextBrowseMode(true);
    state = state.copyWith(
      isNextLoading: true,
      consecutivePreloadExhaustions: browsing.exhaustions,
      isFastBrowseMode: browsing.isFast,
      preloadTarget: browsing.target,
    );
    await _loadFreshCurrent();
  }

  Future<void> switchTag(String? tag) async {
    final normalized = tag?.trim();
    final effectiveTag =
        normalized == null || normalized.isEmpty ? null : normalized;
    if (effectiveTag == state.selectedTag && state.currentImage != null) {
      return;
    }

    _generation += 1;
    await _historyStore.clearPreloadQueue();
    await _tagStore.saveSelectedTag(effectiveTag);
    state = state.copyWith(
      selectedTag: effectiveTag,
      currentMetadata: null,
      adjacentLoadingDelta: null,
      previousAdjacentQueue: const [],
      nextAdjacentQueue: const [],
      preloadQueue: const [],
      preloadTarget: _defaultPreloadTarget,
      isFastBrowseMode: false,
      consecutivePreloadExhaustions: 0,
      isImageZoomed: false,
      isMetadataLoading: false,
      errorMessage: null,
    );

    await _loadFreshCurrent();
  }

  Future<void> loadCurrentMetadata() async {
    final imageId = state.currentImage?.imageId;
    if (imageId == null) {
      state = state.copyWith(errorMessage: '当前图片没有 Image ID，无法获取元数据');
      return;
    }
    if (state.isMetadataLoading || state.currentMetadata?.id == imageId) {
      return;
    }

    final generation = _generation;
    state = state.copyWith(isMetadataLoading: true, errorMessage: null);
    try {
      final metadata = await _repository.fetchImageMetadata(imageId);
      if (!mounted ||
          generation != _generation ||
          state.currentImage?.imageId != imageId) {
        return;
      }
      final galleryId = metadata.gallery?.id;
      final currentImage = state.currentImage;
      final imageWithMetadata = galleryId == null || currentImage == null
          ? currentImage
          : currentImage.copyWith(galleryId: galleryId);
      state = state.copyWith(
        currentImage: imageWithMetadata,
        currentMetadata: metadata,
        isMetadataLoading: false,
      );
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          state.currentImage?.imageId == imageId) {
        state = state.copyWith(
          isMetadataLoading: false,
          errorMessage: _messageForError(error),
        );
      }
    }
  }

  Future<void> useMetadataTag(String value) async {
    final tag = value.trim();
    if (tag.isEmpty) {
      return;
    }
    final existingTag = state.userTags.cast<String?>().firstWhere(
          (item) => item?.toLowerCase() == tag.toLowerCase(),
          orElse: () => null,
        );
    final effectiveTag = existingTag ?? tag;
    if (existingTag == null) {
      final tags = [...state.userTags, tag];
      await _tagStore.saveTags(tags);
      state = state.copyWith(userTags: tags);
    }
    await switchTag(effectiveTag);
  }

  Future<void> toggleCurrentFavorite() async {
    final image = state.currentImage;
    final imageId = image?.imageId;
    if (image == null || imageId == null) {
      state = state.copyWith(errorMessage: '当前图片没有 Image ID，无法收藏');
      return;
    }
    if (state.favoriteLoadingImageId != null) {
      return;
    }

    final existing = state.favoriteImages.cast<FavoriteImage?>().firstWhere(
          (item) => item?.imageId == imageId,
          orElse: () => null,
        );
    state = state.copyWith(
      favoriteLoadingImageId: imageId,
      errorMessage: null,
    );

    try {
      if (existing != null) {
        final favorites = await _favoriteStore.delete(existing);
        if (!mounted) {
          return;
        }
        state = state.copyWith(
          favoriteImages: favorites,
          favoriteLoadingImageId: null,
          errorMessage: '已取消收藏',
        );
        return;
      }

      ImageMetadata? metadata =
          state.currentMetadata?.id == imageId ? state.currentMetadata : null;
      var metadataFailed = false;
      if (metadata == null && !_readQuotaState().isServerLocked) {
        try {
          metadata = await _repository.fetchImageMetadata(imageId);
        } catch (_) {
          metadataFailed = true;
        }
      } else if (metadata == null) {
        metadataFailed = true;
      }
      if (!mounted) {
        return;
      }
      if (state.currentImage?.imageId != imageId) {
        state = state.copyWith(favoriteLoadingImageId: null);
        return;
      }

      final favorite = FavoriteImage.fromRandomImage(
        state.currentImage!,
        favoritedAt: DateTime.now(),
        metadata: metadata,
      );
      final favorites = await _favoriteStore.upsert(favorite);
      if (!mounted) {
        return;
      }
      if (state.currentImage?.imageId != imageId) {
        state = state.copyWith(
          favoriteImages: favorites,
          favoriteLoadingImageId: null,
        );
        return;
      }

      final galleryId = metadata?.gallery?.id;
      final imageWithMetadata =
          galleryId == null ? state.currentImage : state.currentImage!.copyWith(
                galleryId: galleryId,
              );
      state = state.copyWith(
        currentImage: imageWithMetadata,
        currentMetadata: metadata ?? state.currentMetadata,
        favoriteImages: favorites,
        favoriteLoadingImageId: null,
        errorMessage: metadataFailed ? '已收藏，图集信息未补全' : '已收藏',
      );
    } catch (error) {
      if (mounted && state.currentImage?.imageId == imageId) {
        state = state.copyWith(
          favoriteLoadingImageId: null,
          errorMessage: _messageForError(error),
        );
      }
    }
  }

  Future<void> deleteFavorite(FavoriteImage image) async {
    try {
      final favorites = await _favoriteStore.delete(image);
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        favoriteImages: favorites,
        errorMessage: '已取消收藏',
      );
    } catch (error) {
      if (mounted) {
        state = state.copyWith(errorMessage: _messageForError(error));
      }
    }
  }

  Future<void> openAdjacentImage(int delta) async {
    if (delta != -1 && delta != 1) {
      return;
    }
    final current = state.currentImage;
    final imageId = current?.imageId;
    if (current == null || imageId == null) {
      state = state.copyWith(errorMessage: '当前图片没有 Image ID，无法相邻查看');
      return;
    }
    if (state.isInitialLoading ||
        state.isNextLoading ||
        state.adjacentLoadingDelta != null) {
      return;
    }
    final targetId = imageId + delta;
    if (targetId <= 0) {
      state = state.copyWith(errorMessage: '已经到头了');
      return;
    }

    final generation = _generation;
    final queue = delta < 0
        ? [...state.previousAdjacentQueue]
        : [...state.nextAdjacentQueue];
    if (queue.isNotEmpty &&
        queue.first.imageId == targetId &&
        await queue.first.file.exists()) {
      final image = queue.removeAt(0);
      _showAdjacentImage(
        image,
        generation: generation,
        previousImageId: imageId,
        nextQueue: delta > 0 ? queue : null,
        previousQueue: delta < 0 ? queue : null,
      );
      return;
    }

    final cachedTarget = await _cachedHistoryImage(targetId);
    if (!mounted ||
        generation != _generation ||
        state.currentImage?.imageId != imageId) {
      return;
    }
    if (cachedTarget != null) {
      _rememberImageId(cachedTarget.imageId);
      final image = _randomImageFromHistory(cachedTarget);
      _rememberLocalImage(image);
      final historyImages = await _historyStore.touch(cachedTarget);
      if (!mounted ||
          generation != _generation ||
          state.currentImage?.imageId != imageId) {
        return;
      }
      final displayedHistory = historyImages.firstWhere(
        (item) => item.historyId == cachedTarget.historyId,
        orElse: () => cachedTarget,
      );
      final displayedImage = _randomImageFromHistory(displayedHistory);
      _rememberLocalImage(displayedImage);
      state = state.copyWith(
        currentImage: displayedImage,
        currentMetadata: null,
        historyImages: historyImages,
        adjacentLoadingDelta: null,
        isImageZoomed: false,
        errorMessage: null,
        lastLoadError: null,
      );
      return;
    }

    final rememberedTarget = await _cachedRememberedImage(targetId);
    if (!mounted ||
        generation != _generation ||
        state.currentImage?.imageId != imageId) {
      return;
    }
    if (rememberedTarget != null) {
      _showAdjacentImage(
        rememberedTarget,
        generation: generation,
        previousImageId: imageId,
      );
      return;
    }

    if (_readQuotaState().isServerLocked) {
      state = state.copyWith(errorMessage: '歇 60 秒，让服务器也喝口水。');
      return;
    }

    state = state.copyWith(
      adjacentLoadingDelta: delta,
      errorMessage: null,
      lastLoadError: null,
    );

    try {
      final images = await _loadAdjacentBatch(
        startImageId: targetId,
        delta: delta,
        sourceTag: current.sourceTag,
      );
      if (!mounted ||
          generation != _generation ||
          state.currentImage?.imageId != imageId) {
        return;
      }
      if (images.isEmpty) {
        state = state.copyWith(
          adjacentLoadingDelta: null,
          errorMessage: '没有更多相邻图片了',
        );
        return;
      }
      final image = images.first;
      final remaining = images.skip(1).toList();
      _showAdjacentImage(
        image,
        generation: generation,
        previousImageId: imageId,
        nextQueue: delta > 0 ? remaining : null,
        previousQueue: delta < 0 ? remaining : null,
      );
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          state.currentImage?.imageId == imageId) {
        state = state.copyWith(
          adjacentLoadingDelta: null,
          errorMessage: _messageForError(error),
        );
      }
    }
  }

  Future<HistoryImage?> _cachedHistoryImage(
    int imageId,
  ) async {
    for (final image in state.historyImages) {
      if (image.imageId != imageId) {
        continue;
      }
      if (await image.file.exists()) {
        return image;
      }
    }
    return null;
  }

  void _showAdjacentImage(
    RandomImage image, {
    required int generation,
    required int previousImageId,
    List<RandomImage>? nextQueue,
    List<RandomImage>? previousQueue,
  }) {
    _rememberImageId(image.imageId);
    _rememberLocalImage(image);
    if (!mounted ||
        generation != _generation ||
        state.currentImage?.imageId != previousImageId) {
      return;
    }
    state = state.copyWith(
      currentImage: image,
      currentMetadata: null,
      nextAdjacentQueue: nextQueue,
      previousAdjacentQueue: previousQueue,
      adjacentLoadingDelta: null,
      isImageZoomed: false,
      errorMessage: null,
      lastLoadError: null,
    );
    unawaited(_persistDisplayedAdjacentImage(image, generation: generation));
  }

  Future<List<RandomImage>> _loadAdjacentBatch({
    required int startImageId,
    required int delta,
    required String? sourceTag,
  }) async {
    if (_isPreloadingAdjacent) {
      return const <RandomImage>[];
    }

    _isPreloadingAdjacent = true;
    final images = <RandomImage>[];
    try {
      for (var offset = 0; offset < _adjacentPreloadTarget; offset += 1) {
        final imageId = startImageId + delta * offset;
        if (imageId <= 0) {
          break;
        }

        final cached = await _cachedHistoryImage(imageId);
        if (cached != null) {
          final image = _randomImageFromHistory(cached);
          _rememberLocalImage(image);
          images.add(image);
          continue;
        }

        final remembered = await _cachedRememberedImage(imageId);
        if (remembered != null) {
          images.add(remembered);
          continue;
        }
        if (!_readQuotaState().canAcquire) {
          break;
        }

        try {
          images.add(
            await _repository.fetchImageById(imageId, sourceTag: sourceTag),
          );
        } on ImageNotFoundException {
          break;
        } on NiceViewException {
          if (images.isEmpty) {
            rethrow;
          }
          break;
        }
      }
      return images;
    } finally {
      _isPreloadingAdjacent = false;
    }
  }

  Future<void> _persistDisplayedAdjacentImage(
    RandomImage image, {
    required int generation,
  }) async {
    try {
      final historyImages = await _historyStore.upsertFromRandomImage(image);
      if (!mounted ||
          generation != _generation ||
          state.currentImage?.imageId != image.imageId) {
        return;
      }

      final historyImage = historyImages.firstWhere(
        (item) => item.imageId == image.imageId,
        orElse: () => HistoryImage(
          historyId: image.imageId?.toString() ?? image.localFilePath,
          localFilePath: image.localFilePath,
          imageId: image.imageId,
          galleryId: image.galleryId,
          contentType: image.contentType,
          sourceTag: image.sourceTag,
          fetchedAt: image.fetchedAt,
          viewedAt: DateTime.now(),
        ),
      );
      final displayedImage = _randomImageFromHistory(historyImage);
      _rememberLocalImage(displayedImage);
      state = state.copyWith(
        currentImage: displayedImage,
        historyImages: historyImages,
      );
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          state.currentImage?.imageId == image.imageId) {
        state = state.copyWith(errorMessage: _messageForError(error));
      }
    }
  }

  Future<bool> addTag(String value) async {
    final tag = value.trim();
    if (tag.isEmpty) {
      state = state.copyWith(errorMessage: '标签不能为空');
      return false;
    }
    if (tag.length > 60) {
      state = state.copyWith(errorMessage: '标签最长 60 个字符');
      return false;
    }
    if (state.userTags.any((item) => item.toLowerCase() == tag.toLowerCase())) {
      state = state.copyWith(errorMessage: '这个标签已经添加过了');
      return false;
    }

    final tags = [...state.userTags, tag];
    await _tagStore.saveTags(tags);
    state = state.copyWith(userTags: tags);
    await switchTag(tag);
    return true;
  }

  Future<void> deleteTag(String tag) async {
    final tags = state.userTags.where((item) => item != tag).toList();
    await _tagStore.saveTags(tags);
    state = state.copyWith(userTags: tags);
    if (state.selectedTag == tag) {
      await switchTag(null);
    }
  }

  Future<void> downloadCurrentImage() async {
    final current = state.currentImage;
    if (current == null || state.isDownloading) {
      return;
    }

    state = state.copyWith(isDownloading: true, errorMessage: null);
    var imageToSave = current;
    try {
      final localFile = File(imageToSave.localFilePath);
      if (!await localFile.exists()) {
        final imageId = imageToSave.imageId;
        if (imageId == null) {
          throw const NiceViewException('当前图片已丢失，请切换下一张后再下载');
        }
        if (!_readQuotaState().canAcquire) {
          throw QuotaExceededException(_quotaRecoveryMessage());
        }
        imageToSave = await _repository.fetchImageById(
          imageId,
          sourceTag: imageToSave.sourceTag,
        );
        if (mounted && state.currentImage?.imageId == imageId) {
          state = state.copyWith(currentImage: imageToSave);
        }
      }

      await _downloadService.saveImage(imageToSave);
      if (mounted) {
        state = state.copyWith(errorMessage: '已保存到系统相册');
      }
    } catch (error) {
      if (mounted) {
        state = state.copyWith(errorMessage: _messageForError(error));
      }
    } finally {
      if (mounted) {
        state = state.copyWith(isDownloading: false);
      }
    }
  }

  Future<void> deleteHistoryImage(HistoryImage image) async {
    final images = await _historyStore.delete(image);
    if (mounted) {
      state = state.copyWith(historyImages: images);
    }
  }

  Future<void> touchHistoryImage(HistoryImage image) async {
    final images = await _historyStore.touch(image);
    if (mounted) {
      state = state.copyWith(historyImages: images);
    }
  }

  Future<void> removeMissingHistoryImage(HistoryImage image) async {
    final images = await _historyStore.removeMissing(image);
    if (mounted) {
      state = state.copyWith(
        historyImages: images,
        errorMessage: '这张历史图已经不在本机了',
      );
    }
  }

  void clearMessage() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  Future<void> retryCurrent() async {
    await _loadFreshCurrent(isInitial: state.currentImage == null);
  }

  Future<RandomImage?> _restoreLastCurrent(
    List<HistoryImage> historyImages,
  ) async {
    final lastCurrent = await _historyStore.loadLastCurrent();
    final candidates = <HistoryImage>[
      if (lastCurrent != null) lastCurrent,
      ...historyImages,
    ];
    final seen = <String>{};
    for (final image in candidates) {
      if (!seen.add(image.historyId)) {
        continue;
      }
      if (await image.file.exists()) {
        _log('restore last current imageId=${image.imageId}');
        return _randomImageFromHistory(image);
      }
    }
    return null;
  }

  RandomImage _randomImageFromHistory(HistoryImage image) {
    return RandomImage(
      localFilePath: image.localFilePath,
      imageId: image.imageId,
      galleryId: image.galleryId,
      contentType: image.contentType,
      sourceTag: image.sourceTag,
      fetchedAt: image.fetchedAt,
    );
  }

  Future<void> _loadFreshCurrent({bool isInitial = false}) async {
    final generation = ++_generation;
    _log(
      'load current generation=$generation initial=$isInitial '
      'tag=${state.selectedTag ?? '<all>'}',
    );
    state = state.copyWith(
      isInitialLoading: isInitial && state.currentImage == null,
      isNextLoading: !isInitial || state.currentImage != null,
      currentMetadata: null,
      adjacentLoadingDelta: null,
      previousAdjacentQueue: const [],
      nextAdjacentQueue: const [],
      isMetadataLoading: false,
      errorMessage: null,
      lastLoadError: null,
    );

    try {
      final image = await _fetchRandomWithRetry(tag: state.selectedTag);
      if (!mounted || generation != _generation) {
        _log('discard stale image generation=$generation');
        return;
      }
      _rememberImageId(image.imageId);
      _rememberLocalImage(image);
      final historyImages = await _historyStore.upsertFromRandomImage(image);
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        currentImage: image,
        currentMetadata: null,
        adjacentLoadingDelta: null,
        previousAdjacentQueue: const [],
        nextAdjacentQueue: const [],
        historyImages: historyImages,
        isInitialLoading: false,
        isNextLoading: false,
        isImageZoomed: false,
        lastLoadError: null,
      );
      _log(
        'load success generation=$generation imageId=${image.imageId} '
        'path=${image.localFilePath}',
      );
      unawaited(_fillPreloadQueue(generation));
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      final message = _messageForError(error);
      _log('load failed generation=$generation error=$error message=$message');
      state = state.copyWith(
        isInitialLoading: false,
        isNextLoading: false,
        errorMessage: message,
        lastLoadError: message,
      );
    }
  }

  Future<RandomImage> _fetchRandomWithRetry({String? tag}) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await _repository.fetchRandom(tag: tag);
      } on ImageNotFoundException catch (error) {
        lastError = error;
      } on NiceViewException catch (error) {
        if (error is QuotaExceededException ||
            error is ServerLockoutException ||
            error is EmptyTagException) {
          rethrow;
        }
        lastError = error;
        if (attempt < 2) {
          _log('retry random request after transient error: $error');
          await Future<void>.delayed(
              Duration(milliseconds: 500 + attempt * 750));
        }
      }
    }
    throw lastError ?? const ImageNotFoundException('图片不存在');
  }

  Future<void> _persistConsumedPreloadedImage(
    RandomImage image, {
    required int generation,
    required String? selectedTag,
  }) async {
    try {
      final historyImages = await _historyStore.upsertFromRandomImage(image);
      if (!mounted ||
          generation != _generation ||
          selectedTag != state.selectedTag) {
        return;
      }

      final currentImage = historyImages.isEmpty
          ? image
          : _randomImageFromHistory(historyImages.first);
      _rememberLocalImage(currentImage);
      _pendingConsumedPreloadPaths.remove(image.localFilePath);
      final displayedImage = state.currentImage;
      state = displayedImage != null && _isSameImage(displayedImage, image)
          ? state.copyWith(
              currentImage: currentImage,
              historyImages: historyImages,
            )
          : state.copyWith(historyImages: historyImages);

      final preloadQueue = await _historyStore.savePreloadQueue(
        state.preloadQueue,
        selectedTag: selectedTag,
        preservePaths: _pendingConsumedPreloadPaths,
      );
      if (!mounted ||
          generation != _generation ||
          selectedTag != state.selectedTag) {
        return;
      }
      state = state.copyWith(preloadQueue: preloadQueue);
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          selectedTag == state.selectedTag) {
        state = state.copyWith(errorMessage: _messageForError(error));
      }
    } finally {
      _pendingConsumedPreloadPaths.remove(image.localFilePath);
    }
  }

  Future<void> _fillPreloadQueue(int generation) async {
    if (_isPreloading || _readQuotaState().isServerLocked) {
      return;
    }
    _isPreloading = true;
    if (mounted) {
      state = state.copyWith(isPreloading: true);
    }

    var attempts = 0;
    try {
      while (mounted &&
          generation == _generation &&
          state.preloadQueue.length < state.preloadTarget &&
          _readQuotaState().canAcquire &&
          attempts < state.preloadTarget * 4) {
        final quota = _readQuotaState();
        final missing = state.preloadTarget - state.preloadQueue.length;
        final remainingAttempts = state.preloadTarget * 4 - attempts;
        var requestCount = missing;
        if (requestCount > quota.remaining) {
          requestCount = quota.remaining;
        }
        if (requestCount > remainingAttempts) {
          requestCount = remainingAttempts;
        }
        if (requestCount <= 0) {
          break;
        }

        attempts += requestCount;
        _log('preload batch count=$requestCount missing=$missing');
        final results = await Future.wait(
          List.generate(requestCount, (_) async {
            try {
              return _PreloadResult(
                image: await _fetchRandomWithRetry(tag: state.selectedTag),
              );
            } catch (error) {
              return _PreloadResult(error: error);
            }
          }),
        );
        if (!mounted || generation != _generation) {
          return;
        }

        var added = 0;
        final queue = [...state.preloadQueue];
        Object? firstError;
        for (final result in results) {
          final error = result.error;
          if (error != null) {
            if (error is ServerLockoutException) {
              throw error;
            }
            if (error is QuotaExceededException) {
              return;
            }
            firstError ??= error;
            continue;
          }

          final image = result.image;
          if (image == null || _isDuplicate(image, queue)) {
            continue;
          }
          _rememberImageId(image.imageId);
          queue.add(image);
          added += 1;
        }

        if (added > 0) {
          final preloadQueue = await _historyStore.savePreloadQueue(
            queue,
            selectedTag: state.selectedTag,
            preservePaths: _pendingConsumedPreloadPaths,
          );
          if (!mounted || generation != _generation) {
            return;
          }
          state = state.copyWith(preloadQueue: preloadQueue);
        }

        if (added == 0 && firstError != null) {
          break;
        }
      }
    } catch (error) {
      if (mounted) {
        state = state.copyWith(errorMessage: _messageForError(error));
      }
    } finally {
      _isPreloading = false;
      if (mounted) {
        state = state.copyWith(isPreloading: false);
      }
    }
  }

  _BrowseMode _nextBrowseMode(bool queueExhausted) {
    if (!queueExhausted) {
      return _BrowseMode(
        exhaustions: 0,
        isFast: state.isFastBrowseMode,
        target: state.preloadTarget,
      );
    }

    final exhaustions = state.consecutivePreloadExhaustions + 1;
    final isFast = exhaustions >= 2 || state.isFastBrowseMode;
    return _BrowseMode(
      exhaustions: exhaustions,
      isFast: isFast,
      target: _defaultPreloadTarget,
    );
  }

  bool _isDuplicate(RandomImage image, [List<RandomImage>? preloadQueue]) {
    final imageId = image.imageId;
    if (imageId == null) {
      return false;
    }
    if (_recentImageIds.contains(imageId)) {
      return true;
    }
    if (state.currentImage?.imageId == imageId) {
      return true;
    }
    return (preloadQueue ?? state.preloadQueue)
        .any((item) => item.imageId == imageId);
  }

  bool _isSameImage(RandomImage a, RandomImage b) {
    final aId = a.imageId;
    final bId = b.imageId;
    if (aId != null && bId != null) {
      return aId == bId;
    }
    return a.localFilePath == b.localFilePath;
  }

  void _rememberImageId(int? imageId) {
    if (imageId == null) {
      return;
    }
    _recentImageIds.remove(imageId);
    _recentImageIds.addLast(imageId);
    while (_recentImageIds.length > 20) {
      _recentImageIds.removeFirst();
    }
  }

  void _rememberLocalImage(RandomImage image) {
    final imageId = image.imageId;
    if (imageId == null) {
      return;
    }
    _recentLocalImagesById.remove(imageId);
    _recentLocalImagesById[imageId] = image;
    while (_recentLocalImagesById.length > _recentLocalImageLimit) {
      _recentLocalImagesById.remove(_recentLocalImagesById.keys.first);
    }
  }

  Future<RandomImage?> _cachedRememberedImage(int imageId) async {
    final image = _recentLocalImagesById[imageId];
    if (image == null) {
      return null;
    }
    if (await image.file.exists()) {
      return image;
    }
    _recentLocalImagesById.remove(imageId);
    return null;
  }

  String _quotaRecoveryMessage() {
    final wait = _readQuotaState().timeUntilNextAvailable;
    if (wait == null || wait.inSeconds <= 0) {
      return '请求额度已用尽，请稍后再试';
    }
    return '请求额度已用尽，约 ${wait.inSeconds}s 后恢复';
  }

  String _messageForError(Object error) {
    if (error is ServerLockoutException) {
      return '歇 60 秒，让服务器也喝口水。';
    }
    if (error is QuotaExceededException) {
      return _quotaRecoveryMessage();
    }
    if (error is EmptyTagException) {
      return '该标签暂时没有图片';
    }
    if (error is NiceViewException) {
      return error.message;
    }
    return '网络连接失败，稍后再试';
  }

  @override
  void dispose() {
    unawaited(_quotaController.pruneAndSave());
    super.dispose();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[NiceView][Controller] $message');
    }
  }
}

class _PreloadResult {
  const _PreloadResult({
    this.image,
    this.error,
  });

  final RandomImage? image;
  final Object? error;
}

class _BrowseMode {
  const _BrowseMode({
    required this.exhaustions,
    required this.isFast,
    required this.target,
  });

  final int exhaustions;
  final bool isFast;
  final int target;
}
