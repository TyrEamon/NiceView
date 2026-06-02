import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/features/random_image/data/random_image_repository.dart';
import 'package:nice_view/features/random_image/domain/history_image.dart';
import 'package:nice_view/features/random_image/domain/image_metadata.dart';
import 'package:nice_view/features/random_image/domain/random_image.dart';

void main() {
  test('empty history list can be sorted by callers', () {
    final images = HistoryImage.listFromJsonString(null);

    expect(images, isEmpty);
    expect(() => images.sort((a, b) => b.viewedAt.compareTo(a.viewedAt)),
        returnsNormally);
  });

  test('history list parses persisted json', () {
    final fetchedAt = DateTime(2026, 5, 14, 2, 30);
    final viewedAt = DateTime(2026, 5, 14, 2, 31);
    final value = jsonEncode([
      {
        'historyId': '42',
        'localFilePath': '/tmp/nice_view_42.jpg',
        'imageId': 42,
        'galleryId': 7,
        'contentType': 'image/jpeg',
        'sourceTag': 'city',
        'fetchedAt': fetchedAt.toIso8601String(),
        'viewedAt': viewedAt.toIso8601String(),
      },
    ]);

    final images = HistoryImage.listFromJsonString(value);

    expect(images.single.historyId, '42');
    expect(images.single.imageId, 42);
    expect(images.single.viewedAt, viewedAt);
  });

  test('content type maps to stable image extensions', () {
    expect(extensionForContentType('image/png'), '.png');
    expect(extensionForContentType('image/webp; charset=utf-8'), '.webp');
    expect(extensionForContentType('image/gif'), '.gif');
    expect(extensionForContentType(null), '.jpg');
  });

  test('preload queue images parse persisted json', () {
    final fetchedAt = DateTime(2026, 5, 14, 5, 10);
    final value = jsonEncode([
      {
        'localFilePath': '/tmp/preload_99.jpg',
        'imageId': 99,
        'galleryId': 11,
        'contentType': 'image/jpeg',
        'sourceTag': '原神',
        'fetchedAt': fetchedAt.toIso8601String(),
      },
    ]);

    final images = RandomImage.listFromJsonString(value);

    expect(images.single.imageId, 99);
    expect(images.single.sourceTag, '原神');
    expect(images.single.fetchedAt, fetchedAt);
  });

  test('image metadata parses gallery title and tags', () {
    final metadata = ImageMetadata.fromJson({
      'id': 166062,
      'width': 1200,
      'height': 2133,
      'orientation': 'portrait',
      'sort_order': 43,
      'gallery': {
        'id': 2882,
        'title': 'Coser@miko酱ww – 2025年04月订阅 Part01 (54P)',
        'category': 'Cosplay',
      },
      'tags': [
        '2025年04月订阅',
        'Coser@miko酱ww - 2025年04月订阅',
        'Miko Miko Ww',
        'miko酱ww',
      ],
    });

    expect(metadata.gallery?.title, contains('2025年04月订阅'));
    expect(metadata.gallery?.category, 'Cosplay');
    expect(metadata.tags, contains('miko酱ww'));
  });
}
