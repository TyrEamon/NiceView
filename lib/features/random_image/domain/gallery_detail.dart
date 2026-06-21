class GalleryDetail {
  const GalleryDetail({
    required this.id,
    required this.imageCount,
    required this.images,
    this.title,
    this.category,
    this.coverImageId,
    this.totalFromPagination,
  });

  final int id;
  final String? title;
  final String? category;
  final int imageCount;
  final int? coverImageId;
  final List<GalleryImageRef> images;
  final int? totalFromPagination;

  factory GalleryDetail.fromJson(Map<String, Object?> json) {
    final images = _imageRefs(json['images']);
    final pagination = _mapValue(json['images_pagination']);
    final totalFromPagination = pagination == null
        ? null
        : _intValue(pagination, const ['total', 'count', 'image_count']);
    return GalleryDetail(
      id: _requiredInt(json, const ['id', 'gallery_id', 'galleryId']),
      title: _stringValue(json, const ['title', 'name']),
      category: _stringValue(json, const ['category', 'category_name']),
      imageCount: _intValue(json, const ['image_count', 'imageCount']) ??
          totalFromPagination ??
          images.length,
      coverImageId: _intValue(
        json,
        const ['cover_image_id', 'coverImageId', 'cover_id'],
      ),
      images: images,
      totalFromPagination: totalFromPagination,
    );
  }

  static List<GalleryImageRef> _imageRefs(Object? value) {
    if (value is! List<dynamic>) {
      return const <GalleryImageRef>[];
    }
    final images = <GalleryImageRef>[];
    for (final item in value) {
      if (item is Map) {
        try {
          images.add(
            GalleryImageRef.fromJson(Map<String, Object?>.from(item)),
          );
        } on FormatException {
          // Ignore malformed entries while keeping the rest of the gallery.
        }
      }
    }
    return images;
  }
}

class GalleryImageRef {
  const GalleryImageRef({
    required this.id,
    this.sortOrder,
    this.width,
    this.height,
    this.orientation,
  });

  final int id;
  final int? sortOrder;
  final int? width;
  final int? height;
  final String? orientation;

  factory GalleryImageRef.fromJson(Map<String, Object?> json) {
    return GalleryImageRef(
      id: _requiredInt(json, const ['id', 'image_id', 'imageId']),
      sortOrder: _intValue(json, const ['sort_order', 'sortOrder', 'order']),
      width: _intValue(json, const ['width', 'w']),
      height: _intValue(json, const ['height', 'h']),
      orientation: _stringValue(json, const ['orientation']),
    );
  }
}

Map<String, Object?>? _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}

String? _stringValue(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

int _requiredInt(Map<String, Object?> json, List<String> keys) {
  final value = _intValue(json, keys);
  if (value == null) {
    throw const FormatException('required integer field missing');
  }
  return value;
}

int? _intValue(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}
