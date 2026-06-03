import 'dart:convert';

import 'image_metadata.dart';
import 'random_image.dart';

class FavoriteImage {
  const FavoriteImage({
    required this.imageId,
    required this.favoritedAt,
    required this.metadataLoaded,
    this.galleryId,
    this.galleryTitle,
    this.galleryCategory,
    this.width,
    this.height,
    this.orientation,
    this.sortOrder,
    this.tags = const [],
    this.sourceTag,
    this.contentType,
  });

  final int imageId;
  final int? galleryId;
  final String? galleryTitle;
  final String? galleryCategory;
  final int? width;
  final int? height;
  final String? orientation;
  final int? sortOrder;
  final List<String> tags;
  final String? sourceTag;
  final String? contentType;
  final DateTime favoritedAt;
  final bool metadataLoaded;

  String get groupLabel {
    final id = galleryId;
    return id == null ? '未分组' : '图包 #$id';
  }

  Map<String, Object?> toJson() {
    return {
      'imageId': imageId,
      'galleryId': galleryId,
      'galleryTitle': galleryTitle,
      'galleryCategory': galleryCategory,
      'width': width,
      'height': height,
      'orientation': orientation,
      'sortOrder': sortOrder,
      'tags': tags,
      'sourceTag': sourceTag,
      'contentType': contentType,
      'favoritedAt': favoritedAt.toIso8601String(),
      'metadataLoaded': metadataLoaded,
    };
  }

  factory FavoriteImage.fromRandomImage(
    RandomImage image, {
    required DateTime favoritedAt,
    ImageMetadata? metadata,
  }) {
    final gallery = metadata?.gallery;
    return FavoriteImage(
      imageId: image.imageId!,
      galleryId: gallery?.id ?? image.galleryId,
      galleryTitle: gallery?.title,
      galleryCategory: gallery?.category,
      width: metadata?.width,
      height: metadata?.height,
      orientation: metadata?.orientation,
      sortOrder: metadata?.sortOrder,
      tags: metadata?.tags ?? const [],
      sourceTag: image.sourceTag,
      contentType: image.contentType,
      favoritedAt: favoritedAt,
      metadataLoaded: metadata != null,
    );
  }

  static FavoriteImage fromJson(Map<String, Object?> json) {
    return FavoriteImage(
      imageId: json['imageId'] as int,
      galleryId: json['galleryId'] as int?,
      galleryTitle: json['galleryTitle'] as String?,
      galleryCategory: json['galleryCategory'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      orientation: json['orientation'] as String?,
      sortOrder: json['sortOrder'] as int?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      sourceTag: json['sourceTag'] as String?,
      contentType: json['contentType'] as String?,
      favoritedAt: DateTime.parse(json['favoritedAt'] as String),
      metadataLoaded: json['metadataLoaded'] as bool? ?? false,
    );
  }

  static List<FavoriteImage> listFromJsonString(String? value) {
    if (value == null || value.isEmpty) {
      return <FavoriteImage>[];
    }
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded.map((item) {
      return FavoriteImage.fromJson(Map<String, Object?>.from(item as Map));
    }).toList();
  }
}
