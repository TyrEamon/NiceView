import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../services/app_exceptions.dart';
import '../../random_image/domain/favorite_image.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return const BackupService();
});

class BackupService {
  const BackupService();

  static const _channel = MethodChannel('nice_view/backups');

  BackupDocument createBackupDocument({
    required List<FavoriteImage> favorites,
  }) {
    final exportedAt = DateTime.now();
    final payload = jsonEncode({
      'version': 1,
      'exportedAt': exportedAt.toIso8601String(),
      'favorites': favorites.map((image) => image.toJson()).toList(),
    });
    return BackupDocument(
      fileName: _fileName(exportedAt),
      bytes: Uint8List.fromList(utf8.encode(payload)),
    );
  }

  Future<String> exportBackup({
    required List<FavoriteImage> favorites,
  }) async {
    final document = createBackupDocument(favorites: favorites);

    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('exportJson', {
              'bytes': document.bytes,
              'fileName': document.fileName,
            }) ??
            document.fileName;
      } on PlatformException catch (error) {
        throw NiceViewException(error.message ?? '备份导出失败');
      }
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, document.fileName));
    await file.writeAsBytes(document.bytes, flush: true);
    return file.path;
  }

  Future<BackupPayload> importBackup() async {
    late final Uint8List bytes;
    if (Platform.isAndroid) {
      try {
        bytes = await _channel.invokeMethod<Uint8List>('importJson') ??
            Uint8List(0);
      } on PlatformException catch (error) {
        throw NiceViewException(error.message ?? '备份导入失败');
      }
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'niceview-backup.json'));
      if (!await file.exists()) {
        throw NiceViewException('没有找到备份文件：${file.path}');
      }
      bytes = await file.readAsBytes();
    }

    if (bytes.isEmpty) {
      throw const NiceViewException('备份文件为空');
    }
    return parseBackupBytes(bytes);
  }

  BackupPayload parseBackupBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const NiceViewException('备份文件为空');
    }
    return BackupPayload.fromJsonString(utf8.decode(bytes));
  }

  String _fileName(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return 'niceview-backup-'
        '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}.json';
  }
}

class BackupDocument {
  const BackupDocument({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

class BackupPayload {
  const BackupPayload({
    required this.favorites,
  });

  final List<FavoriteImage> favorites;

  factory BackupPayload.fromJsonString(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        throw const FormatException('root is not an object');
      }
      final map = Map<String, Object?>.from(decoded);
      return BackupPayload(
        favorites: _favoritesFrom(map['favorites']),
      );
    } on FormatException catch (error) {
      throw NiceViewException('备份 JSON 解析失败：${error.message}');
    } on TypeError {
      throw const NiceViewException('备份 JSON 格式不完整');
    }
  }

  static List<FavoriteImage> _favoritesFrom(Object? value) {
    if (value is! List<dynamic>) {
      return <FavoriteImage>[];
    }
    return value.map((item) {
      return FavoriteImage.fromJson(Map<String, Object?>.from(item as Map));
    }).toList();
  }

}
