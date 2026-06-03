import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/shared_preferences_provider.dart';
import '../domain/favorite_image.dart';

final favoriteStoreProvider = Provider<FavoriteStore>((ref) {
  return FavoriteStore(ref.watch(sharedPreferencesProvider));
});

class FavoriteStore {
  FavoriteStore(this._preferences);

  static const _favoritesKey = 'nice_view.favorite_images';

  final SharedPreferences _preferences;

  Future<List<FavoriteImage>> load() async {
    final images = FavoriteImage.listFromJsonString(
      _preferences.getString(_favoritesKey),
    );
    images.sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    return images;
  }

  Future<List<FavoriteImage>> upsert(FavoriteImage image) async {
    final images = await load();
    images.removeWhere((item) => item.imageId == image.imageId);
    images.insert(0, image);
    await _save(images);
    return images;
  }

  Future<List<FavoriteImage>> delete(FavoriteImage image) async {
    final images = await load();
    images.removeWhere((item) => item.imageId == image.imageId);
    await _save(images);
    return images;
  }

  Future<List<FavoriteImage>> merge(List<FavoriteImage> incoming) async {
    final images = await load();
    final byId = <int, FavoriteImage>{
      for (final image in images) image.imageId: image,
    };
    for (final image in incoming) {
      final existing = byId[image.imageId];
      if (existing == null ||
          image.favoritedAt.isAfter(existing.favoritedAt) ||
          (!existing.metadataLoaded && image.metadataLoaded)) {
        byId[image.imageId] = image;
      }
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    await _save(merged);
    return merged;
  }

  Future<void> _save(List<FavoriteImage> images) async {
    await _preferences.setString(
      _favoritesKey,
      jsonEncode(images.map((image) => image.toJson()).toList()),
    );
  }
}
