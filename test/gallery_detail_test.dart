import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/features/random_image/domain/gallery_detail.dart';

void main() {
  test('gallery detail parses real Veil sample', () async {
    final file = File('test/fixtures/gallery-13292.json');
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    final detail = GalleryDetail.fromJson(Map<String, Object?>.from(json));

    expect(detail.id, 13292);
    expect(detail.title, 'AmourAngels Presenting – Velana Part1 (53P)');
    expect(detail.category, 'Europe');
    expect(detail.imageCount, 53);
    expect(detail.coverImageId, 740001);
    expect(detail.totalFromPagination, 53);
    expect(detail.images, hasLength(20));

    final first = detail.images.first;
    expect(first.id, 740001);
    expect(first.sortOrder, 1);
    expect(first.width, 1200);
    expect(first.height, 1800);
    expect(first.orientation, 'portrait');

    final last = detail.images.last;
    expect(last.id, 740020);
    expect(last.sortOrder, 20);
    expect(last.orientation, 'landscape');
  });

  test('gallery detail uses tolerant numeric fallbacks', () {
    final detail = GalleryDetail.fromJson({
      'gallery_id': '7',
      'name': 'Example Gallery',
      'images': [
        {
          'image_id': '100',
          'sortOrder': '1',
          'w': 1200.7,
          'h': '800',
          'orientation': 'landscape',
        },
      ],
      'images_pagination': {'total': '12'},
    });

    expect(detail.id, 7);
    expect(detail.title, 'Example Gallery');
    expect(detail.imageCount, 12);
    expect(detail.totalFromPagination, 12);
    expect(detail.images.single.id, 100);
    expect(detail.images.single.sortOrder, 1);
    expect(detail.images.single.width, 1200);
    expect(detail.images.single.height, 800);
  });
}
