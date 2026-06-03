import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/top_snack_bar.dart';
import '../../../services/app_exceptions.dart';
import '../../../services/download_service.dart';
import '../data/random_image_repository.dart';
import '../domain/favorite_image.dart';
import '../domain/random_image.dart';

const _favoritePreloadAhead = 2;

class FavoritePreviewPage extends ConsumerStatefulWidget {
  const FavoritePreviewPage({
    required this.title,
    required this.favorites,
    required this.initialIndex,
    super.key,
  });

  final String title;
  final List<FavoriteImage> favorites;
  final int initialIndex;

  @override
  ConsumerState<FavoritePreviewPage> createState() =>
      _FavoritePreviewPageState();
}

class _FavoritePreviewPageState extends ConsumerState<FavoritePreviewPage> {
  late final PageController _pageController;
  late int _index;
  final Map<int, RandomImage> _imagesById = <int, RandomImage>{};
  final Map<int, String> _errorsById = <int, String>{};
  final Set<int> _loadingIds = <int>{};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.favorites.isEmpty ? 0 : widget.favorites.length - 1;
    _index = widget.initialIndex.clamp(0, maxIndex).toInt();
    _pageController = PageController(initialPage: _index);
    _startLoadForIndex(_index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.favorites.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: niceText,
        ),
      );
    }

    final favorite = widget.favorites[_index];
    final currentImage = _imagesById[favorite.imageId];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.favorites.length,
            onPageChanged: (index) {
              setState(() => _index = index);
              _startLoadForIndex(index);
            },
            itemBuilder: (context, index) {
              final favorite = widget.favorites[index];
              final image = _imagesById[favorite.imageId];
              return _FavoritePreviewStage(
                favorite: favorite,
                image: image,
                isCurrent: index == _index,
                isLoading: _loadingIds.contains(favorite.imageId),
                errorMessage: _errorsById[favorite.imageId],
                onRetry: () => _startLoadForIndex(index),
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: IconButton.filled(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.42),
                    foregroundColor: niceText,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(72, 18, 86, 0),
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: niceMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 18, top: 20),
                child: Text(
                  '${_index + 1} / ${widget.favorites.length}',
                  style: const TextStyle(color: niceMuted, fontSize: 13),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 22, bottom: 22),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      '#${favorite.imageId}',
                      style: const TextStyle(
                        color: niceText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 22, bottom: 22),
                child: IconButton.filled(
                  tooltip: '保存图片',
                  onPressed: currentImage == null || _isSaving
                      ? null
                      : _saveCurrentImage,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.50),
                    foregroundColor: niceText,
                    disabledBackgroundColor:
                        Colors.black.withValues(alpha: 0.32),
                    disabledForegroundColor: niceText.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _loadForIndex(
    int index, {
    bool silent = false,
    bool preloadAfter = true,
  }) async {
    if (index < 0 || index >= widget.favorites.length) {
      return false;
    }
    final favorite = widget.favorites[index];
    final imageId = favorite.imageId;
    if (_imagesById.containsKey(imageId)) {
      if (preloadAfter) {
        unawaited(_preloadAfter(index));
      }
      return true;
    }
    if (_loadingIds.contains(imageId)) {
      return !silent;
    }

    setState(() {
      _loadingIds.add(imageId);
      if (!silent) {
        _errorsById.remove(imageId);
      }
    });

    try {
      final image = await ref.read(randomImageRepositoryProvider).fetchImageById(
            imageId,
            sourceTag: favorite.sourceTag,
          );
      if (!mounted) {
        return false;
      }
      setState(() {
        _imagesById[imageId] = image;
        _errorsById.remove(imageId);
      });
      if (preloadAfter) {
        unawaited(_preloadAfter(index));
      }
      return true;
    } catch (error) {
      if (mounted && !silent) {
        setState(() => _errorsById[imageId] = _messageForError(error));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _loadingIds.remove(imageId));
      }
    }
  }

  void _startLoadForIndex(int index) {
    unawaited(_loadForIndex(index).then<void>((_) {}));
  }

  Future<void> _preloadAfter(int index) async {
    for (var offset = 1; offset <= _favoritePreloadAhead; offset += 1) {
      final ok = await _loadForIndex(
        index + offset,
        silent: true,
        preloadAfter: false,
      );
      if (!ok) {
        return;
      }
    }
  }

  Future<void> _saveCurrentImage() async {
    if (_isSaving || widget.favorites.isEmpty) {
      return;
    }
    final image = _imagesById[widget.favorites[_index].imageId];
    if (image == null) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(downloadServiceProvider).saveImage(image);
      if (!mounted) {
        return;
      }
      showTopSnackBar(context, '已保存到系统相册');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showTopSnackBar(context, _messageForError(error));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _messageForError(Object error) {
    if (error is ServerLockoutException) {
      return '歇 60 秒，让服务器也喝口水。';
    }
    if (error is QuotaExceededException) {
      return '请求额度已用尽，请稍后再试';
    }
    if (error is ImageNotFoundException) {
      return '图片不存在';
    }
    if (error is NiceViewException) {
      return error.message;
    }
    return '加载失败，请稍后再试';
  }
}

class _FavoritePreviewStage extends StatefulWidget {
  const _FavoritePreviewStage({
    required this.favorite,
    required this.image,
    required this.isCurrent,
    required this.isLoading,
    required this.onRetry,
    this.errorMessage,
  });

  final FavoriteImage favorite;
  final RandomImage? image;
  final bool isCurrent;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  State<_FavoritePreviewStage> createState() => _FavoritePreviewStageState();
}

class _FavoritePreviewStageState extends State<_FavoritePreviewStage>
    with SingleTickerProviderStateMixin {
  late final TransformationController _controller;
  late final AnimationController _resetAnimationController;
  Animation<Matrix4>? _resetAnimation;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController()..addListener(_syncZoomState);
    _resetAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _resetAnimation;
        if (animation != null) {
          _controller.value = animation.value;
        }
      });
  }

  @override
  void didUpdateWidget(covariant _FavoritePreviewStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image?.localFilePath != widget.image?.localFilePath) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _resetAnimationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: image == null ? null : _reset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image == null)
            _FavoritePlaceholder(
              favorite: widget.favorite,
              isCurrent: widget.isCurrent,
              isLoading: widget.isLoading,
              errorMessage: widget.errorMessage,
              onRetry: widget.onRetry,
            )
          else
            InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 4,
              panEnabled: _isZoomed,
              boundaryMargin: const EdgeInsets.all(96),
              child: SizedBox.expand(
                child: Image.file(
                  File(image.localFilePath),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) {
                    return _FavoritePlaceholder(
                      favorite: widget.favorite,
                      isCurrent: widget.isCurrent,
                      isLoading: false,
                      errorMessage: '图片文件不可用',
                      onRetry: widget.onRetry,
                    );
                  },
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedOpacity(
                opacity: _isZoomed ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !_isZoomed,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 52),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _reset,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.restart_alt_rounded, size: 18),
                              SizedBox(width: 6),
                              Text(
                                '还原',
                                style: TextStyle(
                                  color: niceText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _syncZoomState() {
    final value = _controller.value.storage;
    final zoomed =
        value[0] > 1.01 || value[12].abs() > 0.5 || value[13].abs() > 0.5;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _reset() {
    _resetAnimation = Matrix4Tween(
      begin: _controller.value,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(
        parent: _resetAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _resetAnimationController.forward(from: 0);
  }
}

class _FavoritePlaceholder extends StatelessWidget {
  const _FavoritePlaceholder({
    required this.favorite,
    required this.isCurrent,
    required this.isLoading,
    required this.onRetry,
    this.errorMessage,
  });

  final FavoriteImage favorite;
  final bool isCurrent;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#${favorite.imageId}',
              style: const TextStyle(
                color: niceText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (favorite.galleryTitle != null &&
                favorite.galleryTitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                favorite.galleryTitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: niceMuted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            if (isLoading)
              const SizedBox.square(
                dimension: 30,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else if (message != null && message.isNotEmpty) ...[
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: niceMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              IconButton.filled(
                onPressed: isCurrent ? onRetry : null,
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  foregroundColor: niceText,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
