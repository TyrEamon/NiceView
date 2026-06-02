class ImageMetadata {
  const ImageMetadata({
    required this.id,
    required this.width,
    required this.height,
    required this.tags,
    this.orientation,
    this.sortOrder,
    this.gallery,
  });

  final int id;
  final int width;
  final int height;
  final String? orientation;
  final int? sortOrder;
  final ImageGalleryMetadata? gallery;
  final List<String> tags;

  factory ImageMetadata.fromJson(Map<String, Object?> json) {
    final gallery = json['gallery'];
    return ImageMetadata(
      id: json['id'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      orientation: json['orientation'] as String?,
      sortOrder: json['sort_order'] as int?,
      gallery: gallery is Map
          ? ImageGalleryMetadata.fromJson(Map<String, Object?>.from(gallery))
          : null,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class ImageGalleryMetadata {
  const ImageGalleryMetadata({
    required this.id,
    this.title,
    this.category,
  });

  final int id;
  final String? title;
  final String? category;

  factory ImageGalleryMetadata.fromJson(Map<String, Object?> json) {
    return ImageGalleryMetadata(
      id: json['id'] as int,
      title: json['title'] as String?,
      category: json['category'] as String?,
    );
  }
}
