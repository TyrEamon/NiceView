import 'dart:convert';

class TagInfo {
  const TagInfo({
    required this.name,
    this.galleryCount,
    this.imageCount,
  });

  final String name;
  final int? galleryCount;
  final int? imageCount;

  int get sortCount => galleryCount ?? imageCount ?? 0;

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'galleryCount': galleryCount,
      'imageCount': imageCount,
    };
  }

  static TagInfo fromJson(Map<String, Object?> json) {
    return TagInfo(
      name: _stringValue(json, const ['name', 'tag', 'title', 'label']),
      galleryCount: _intValue(
        json,
        const ['gallery_count', 'galleryCount', 'galleries', 'count'],
      ),
      imageCount: _intValue(
        json,
        const ['image_count', 'imageCount', 'images'],
      ),
    );
  }

  static List<TagInfo> listFromJsonValue(Object? value) {
    if (value == null) {
      return <TagInfo>[];
    }
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! List<dynamic>) {
      return <TagInfo>[];
    }
    return decoded.map((item) {
      if (item is String) {
        return TagInfo(name: item);
      }
      return TagInfo.fromJson(Map<String, Object?>.from(item as Map));
    }).toList();
  }

  static String _stringValue(
    Map<String, Object?> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    throw const FormatException('标签名称缺失');
  }

  static int? _intValue(
    Map<String, Object?> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }
}
