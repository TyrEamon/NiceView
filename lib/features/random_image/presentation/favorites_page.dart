import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/top_snack_bar.dart';
import '../domain/favorite_image.dart';
import 'favorite_preview_page.dart';
import 'random_image_controller.dart';

enum _FavoriteMode { all, gallery }

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  _FavoriteMode _mode = _FavoriteMode.all;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      randomImageControllerProvider.select((state) => state.errorMessage),
      (previous, next) {
        if (next == null) {
          return;
        }
        showTopSnackBar(context, next);
        ref.read(randomImageControllerProvider.notifier).clearMessage();
      },
    );

    final favorites = ref.watch(
      randomImageControllerProvider.select((state) => state.favoriteImages),
    );
    return Scaffold(
      backgroundColor: niceBlack,
      appBar: AppBar(
        backgroundColor: niceBlack,
        foregroundColor: niceText,
        title: const Text('收藏夹'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<_FavoriteMode>(
              segments: const [
                ButtonSegment(
                  value: _FavoriteMode.all,
                  label: Text('全部'),
                  icon: Icon(Icons.apps_rounded),
                ),
                ButtonSegment(
                  value: _FavoriteMode.gallery,
                  label: Text('图包'),
                  icon: Icon(Icons.folder_rounded),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _mode = selection.first);
              },
            ),
          ),
          Expanded(
            child: favorites.isEmpty
                ? const _EmptyFavorites()
                : _mode == _FavoriteMode.all
                    ? _AllFavoritesView(
                        favorites: favorites,
                        onOpen: _openPreview,
                        onDelete: _confirmDelete,
                      )
                    : _GalleryFavoritesView(
                        favorites: favorites,
                        onOpen: _openPreview,
                        onDelete: _confirmDelete,
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPreview(
    String title,
    List<FavoriteImage> favorites,
    FavoriteImage image,
  ) async {
    final index = favorites.indexWhere((item) => item.imageId == image.imageId);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FavoritePreviewPage(
          title: title,
          favorites: favorites,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(FavoriteImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF191A1C),
          title: const Text('取消收藏'),
          content: Text('从收藏夹移除 #${image.imageId}？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(randomImageControllerProvider.notifier).deleteFavorite(
            image,
          );
    }
  }
}

class _AllFavoritesView extends StatelessWidget {
  const _AllFavoritesView({
    required this.favorites,
    required this.onOpen,
    required this.onDelete,
  });

  final List<FavoriteImage> favorites;
  final Future<void> Function(
    String title,
    List<FavoriteImage> favorites,
    FavoriteImage image,
  ) onOpen;
  final ValueChanged<FavoriteImage> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _GroupHeader(
          title: '全部收藏',
          count: favorites.length,
        ),
        const SizedBox(height: 10),
        _FavoriteChipWrap(
          title: '全部收藏',
          favorites: favorites,
          onOpen: onOpen,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

class _GalleryFavoritesView extends StatelessWidget {
  const _GalleryFavoritesView({
    required this.favorites,
    required this.onOpen,
    required this.onDelete,
  });

  final List<FavoriteImage> favorites;
  final Future<void> Function(
    String title,
    List<FavoriteImage> favorites,
    FavoriteImage image,
  ) onOpen;
  final ValueChanged<FavoriteImage> onDelete;

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups(favorites);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final group = groups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeader(
              title: group.title,
              subtitle: group.subtitle,
              count: group.images.length,
            ),
            const SizedBox(height: 10),
            _FavoriteChipWrap(
              title: group.title,
              favorites: group.images,
              onOpen: onOpen,
              onDelete: onDelete,
            ),
          ],
        );
      },
    );
  }

  List<_FavoriteGroup> _buildGroups(List<FavoriteImage> favorites) {
    final groups = <String, _FavoriteGroup>{};
    for (final favorite in favorites) {
      final key = favorite.galleryId?.toString() ?? 'ungrouped';
      final group = groups.putIfAbsent(key, () {
        return _FavoriteGroup(
          title: favorite.groupLabel,
          subtitle: favorite.galleryTitle,
          images: <FavoriteImage>[],
          newestAt: favorite.favoritedAt,
        );
      });
      group.images.add(favorite);
      if (favorite.favoritedAt.isAfter(group.newestAt)) {
        group.newestAt = favorite.favoritedAt;
      }
      if ((group.subtitle == null || group.subtitle!.isEmpty) &&
          favorite.galleryTitle != null &&
          favorite.galleryTitle!.isNotEmpty) {
        group.subtitle = favorite.galleryTitle;
      }
    }
    final result = groups.values.toList()
      ..sort((a, b) => b.newestAt.compareTo(a.newestAt));
    for (final group in result) {
      group.images.sort((a, b) => a.imageId.compareTo(b.imageId));
    }
    return result;
  }
}

class _FavoriteChipWrap extends StatelessWidget {
  const _FavoriteChipWrap({
    required this.title,
    required this.favorites,
    required this.onOpen,
    required this.onDelete,
  });

  final String title;
  final List<FavoriteImage> favorites;
  final Future<void> Function(
    String title,
    List<FavoriteImage> favorites,
    FavoriteImage image,
  ) onOpen;
  final ValueChanged<FavoriteImage> onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final favorite in favorites)
          InputChip(
            label: Text('#${favorite.imageId}'),
            onPressed: () {
              unawaited(onOpen(title, favorites, favorite));
            },
            onDeleted: () => onDelete(favorite),
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: niceText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$count 张',
              style: const TextStyle(color: niceMuted, fontSize: 13),
            ),
          ],
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: niceMuted, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '暂无收藏',
        style: TextStyle(color: niceMuted),
      ),
    );
  }
}

class _FavoriteGroup {
  _FavoriteGroup({
    required this.title,
    required this.images,
    required this.newestAt,
    this.subtitle,
  });

  final String title;
  String? subtitle;
  final List<FavoriteImage> images;
  DateTime newestAt;
}
