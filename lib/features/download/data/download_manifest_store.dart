import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/shared_preferences_provider.dart';

final downloadManifestStoreProvider = Provider<DownloadManifestStore>((ref) {
  return DownloadManifestStore(ref.watch(sharedPreferencesProvider));
});

class DownloadManifestStore {
  DownloadManifestStore(this._preferences);

  static const _keyPrefix = 'nice_view.gallery_download_manifest.';

  final SharedPreferences _preferences;

  Set<int> downloadedImageIds(int galleryId) {
    final values = _preferences.getStringList(_key(galleryId)) ?? const [];
    return values.map(int.tryParse).whereType<int>().toSet();
  }

  Future<void> markDownloaded(int galleryId, int imageId) async {
    final ids = downloadedImageIds(galleryId)..add(imageId);
    final values = ids.map((id) => id.toString()).toList()..sort();
    await _preferences.setStringList(_key(galleryId), values);
  }

  String _key(int galleryId) => '$_keyPrefix$galleryId';
}
