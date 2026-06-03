import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../random_image/data/veil_api_client.dart';
import '../domain/tag_info.dart';

final tagLibraryRepositoryProvider = Provider<TagLibraryRepository>((ref) {
  return TagLibraryRepository(ref.watch(veilApiClientProvider));
});

class TagLibrarySnapshot {
  const TagLibrarySnapshot({
    required this.tags,
    required this.fetchedAt,
  });

  final List<TagInfo> tags;
  final DateTime fetchedAt;
}

class TagLibraryRepository {
  TagLibraryRepository(this._apiClient);

  final VeilApiClient _apiClient;

  Future<TagLibrarySnapshot?> loadCached() async {
    final file = await _cacheFile();
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString()) as Map;
      return TagLibrarySnapshot(
        tags: TagInfo.listFromJsonValue(decoded['tags']),
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
      );
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<TagLibrarySnapshot> refresh() async {
    final tags = await _apiClient.tags();
    tags.sort((a, b) {
      final countCompare = b.sortCount.compareTo(a.sortCount);
      if (countCompare != 0) {
        return countCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final snapshot = TagLibrarySnapshot(
      tags: tags,
      fetchedAt: DateTime.now(),
    );
    await _save(snapshot);
    return snapshot;
  }

  Future<void> _save(TagLibrarySnapshot snapshot) async {
    final file = await _cacheFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'fetchedAt': snapshot.fetchedAt.toIso8601String(),
        'tags': snapshot.tags.map((tag) => tag.toJson()).toList(),
      }),
      flush: true,
    );
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'tags_cache.json'));
  }
}
