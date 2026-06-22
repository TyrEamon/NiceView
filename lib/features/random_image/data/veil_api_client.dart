import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exceptions.dart';
import '../../../services/desktop_settings.dart';
import '../../../services/rate_limiter.dart';
import '../../tags/domain/tag_info.dart';
import '../domain/gallery_detail.dart';
import '../domain/image_metadata.dart';

final veilApiClientProvider = Provider<VeilApiClient>((ref) {
  final client = VeilApiClient(
    ref.watch(rateLimiterProvider.notifier),
    readSettings: () => ref.read(desktopSettingsProvider),
  );
  ref.onDispose(client.close);
  return client;
});

class VeilImageResponse {
  const VeilImageResponse({
    required this.bytes,
    required this.contentType,
    this.imageId,
    this.galleryId,
  });

  final List<int> bytes;
  final String? contentType;
  final int? imageId;
  final int? galleryId;
}

class VeilApiClient {
  VeilApiClient(
    this._rateLimiter, {
    required DesktopSettings Function() readSettings,
  })  : _readSettings = readSettings,
        _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 60);
    _client.idleTimeout = const Duration(seconds: 15);
    if (Platform.isWindows) {
      _client.findProxy = (_) {
        final settings = _readSettings();
        return settings.hasProxy ? settings.proxyRule : 'DIRECT';
      };
    }
  }

  static const _host = 'veil.ortlinde.com';
  static const _receiveTimeout = Duration(seconds: 90);

  final HttpClient _client;
  final RateLimiter _rateLimiter;
  final DesktopSettings Function() _readSettings;

  Future<VeilImageResponse> random({String? tag}) {
    return _imageRequest(
      '/v1/random',
      queryParameters: tag == null ? null : {'tag': tag},
    );
  }

  Future<VeilImageResponse> imageById(int imageId) {
    return _imageRequest('/v1/image/$imageId');
  }

  void close() {
    _client.close(force: true);
  }

  Future<GalleryDetail> gallery(int id) async {
    final decoded = await _jsonRequest('/v1/gallery/$id');
    if (decoded is! Map) {
      throw const NiceViewException('图集数据格式不完整');
    }
    try {
      return GalleryDetail.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException catch (error) {
      _log('gallery parse error: $error');
      throw const NiceViewException('图集数据解析失败');
    } on TypeError catch (error) {
      _log('gallery shape error: $error');
      throw const NiceViewException('图集数据格式不完整');
    }
  }

  Future<ImageMetadata> imageMetadataById(int imageId) async {
    final uri = Uri.https(_host, '/v1/image/$imageId/meta');
    _log('GET $uri');

    late final HttpClientResponse response;
    try {
      await _rateLimiter.acquire();
      final request = await _client.getUrl(uri).timeout(_receiveTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'NiceView/1.0')
        ..set(HttpHeaders.connectionHeader, 'close');
      response = await request.close().timeout(_receiveTimeout);
    } on TimeoutException catch (error) {
      _log('metadata request timeout: $error');
      throw const NiceViewException('元数据请求超时，稍后再试');
    } on SocketException catch (error) {
      _log('metadata socket error: $error');
      throw const NiceViewException('网络连接失败，稍后再试');
    } on HandshakeException catch (error) {
      _log('metadata tls error: $error');
      throw const NiceViewException('安全连接失败，稍后再试');
    } on HttpException catch (error) {
      _log('metadata http error: $error');
      throw NiceViewException(error.message);
    }

    final statusCode = response.statusCode;
    final contentType = response.headers.contentType?.mimeType ??
        response.headers.value(HttpHeaders.contentTypeHeader);
    _log('metadata response $statusCode type=$contentType');

    late final List<int> bytes;
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_receiveTimeout)) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    } on TimeoutException catch (error) {
      _log('metadata body timeout: $error');
      throw const NiceViewException('元数据下载超时，稍后再试');
    } on SocketException catch (error) {
      _log('metadata body socket error: $error');
      throw const NiceViewException('元数据下载中断，稍后再试');
    } on HttpException catch (error) {
      _log('metadata body http error: $error');
      throw const NiceViewException('元数据下载中断，稍后再试');
    }

    if (statusCode == 429) {
      await _rateLimiter.noteLockout();
      throw const ServerLockoutException('请求太快了，请稍后再试');
    }
    if (statusCode == 404) {
      throw const ImageNotFoundException('图片不存在');
    }
    if (statusCode == 403) {
      await _rateLimiter.noteLockout();
      throw const ServerLockoutException('IP 已被封禁，请 30 分钟后再试');
    }
    if (statusCode == 503) {
      throw const NiceViewException('接口已被管理员关闭');
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw NiceViewException('服务器暂时不可用：$statusCode');
    }

    try {
      return ImageMetadata.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
      );
    } on FormatException catch (error) {
      _log('metadata parse error: $error');
      throw const NiceViewException('元数据解析失败');
    } on TypeError catch (error) {
      _log('metadata shape error: $error');
      throw const NiceViewException('元数据格式不完整');
    }
  }

  Future<List<TagInfo>> tags() async {
    final decoded = await _jsonRequest(
      '/v1/tags',
      queryParameters: const {
        'limit': '20000',
        'offset': '0',
      },
    );
    final tags = <TagInfo>[];
    for (final item in _tagItems(decoded)) {
      try {
        if (item is String) {
          tags.add(TagInfo(name: item));
        } else if (item is Map) {
          tags.add(TagInfo.fromJson(Map<String, Object?>.from(item)));
        }
      } on FormatException catch (error) {
        _log('tag parse skipped: $error');
      }
    }
    return tags;
  }

  Iterable<dynamic> _tagItems(Object? decoded) {
    if (decoded is List<dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      for (final key in const ['tags', 'items', 'data']) {
        final value = decoded[key];
        if (value is List<dynamic>) {
          return value;
        }
      }
    }
    return const <dynamic>[];
  }

  Future<Object?> _jsonRequest(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.https(_host, path, queryParameters);
    _log('GET $uri');

    late final HttpClientResponse response;
    try {
      await _rateLimiter.acquire();
      final request = await _client.getUrl(uri).timeout(_receiveTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'NiceView/1.0')
        ..set(HttpHeaders.connectionHeader, 'close');
      response = await request.close().timeout(_receiveTimeout);
    } on TimeoutException catch (error) {
      _log('json request timeout: $error');
      throw const NiceViewException('标签请求超时，稍后再试');
    } on SocketException catch (error) {
      _log('json socket error: $error');
      throw const NiceViewException('网络连接失败，稍后再试');
    } on HandshakeException catch (error) {
      _log('json tls error: $error');
      throw const NiceViewException('安全连接失败，稍后再试');
    } on HttpException catch (error) {
      _log('json http error: $error');
      throw NiceViewException(error.message);
    }

    final statusCode = response.statusCode;
    late final List<int> bytes;
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_receiveTimeout)) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    } on TimeoutException catch (error) {
      _log('json body timeout: $error');
      throw const NiceViewException('标签下载超时，稍后再试');
    } on SocketException catch (error) {
      _log('json body socket error: $error');
      throw const NiceViewException('标签下载中断，稍后再试');
    } on HttpException catch (error) {
      _log('json body http error: $error');
      throw const NiceViewException('标签下载中断，稍后再试');
    }

    if (statusCode == 429) {
      await _rateLimiter.noteLockout();
      throw const ServerLockoutException('请求太快了，请稍后再试');
    }
    if (statusCode == 403) {
      await _rateLimiter.noteLockout();
      throw const ServerLockoutException('IP 已被封禁，请 30 分钟后再试');
    }
    if (statusCode == 503) {
      throw const NiceViewException('接口已被管理员关闭');
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw NiceViewException('服务器暂时不可用：$statusCode');
    }

    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      _log('json parse error: $error');
      throw const NiceViewException('标签数据解析失败');
    }
  }

  Future<VeilImageResponse> _imageRequest(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    final normalizedQuery = queryParameters?.map(
      (key, value) => MapEntry(key, value?.toString()),
    );
    final uri = Uri.https(_host, path, normalizedQuery);
    _log('GET $uri');

    late final HttpClientResponse response;
    try {
      await _rateLimiter.acquire();
      final request = await _client.getUrl(uri).timeout(_receiveTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8')
        ..set(HttpHeaders.userAgentHeader, 'NiceView/1.0')
        ..set(HttpHeaders.connectionHeader, 'close');
      response = await request.close().timeout(_receiveTimeout);
    } on TimeoutException catch (error) {
      _log('request timeout: $error');
      throw const NiceViewException('网络请求超时，稍后再试');
    } on SocketException catch (error) {
      _log('socket error: $error');
      throw const NiceViewException('网络连接失败，稍后再试');
    } on HandshakeException catch (error) {
      _log('tls error: $error');
      throw const NiceViewException('安全连接失败，稍后再试');
    } on HttpException catch (error) {
      _log('http error: $error');
      throw NiceViewException(error.message);
    }

    final statusCode = response.statusCode;
    final contentType = response.headers.contentType?.mimeType ??
        response.headers.value(HttpHeaders.contentTypeHeader);
    _log('response $statusCode type=$contentType');

    late final List<int> bytes;
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_receiveTimeout)) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
      _log('received ${bytes.length} bytes');
    } on TimeoutException catch (error) {
      _log('body timeout: $error');
      throw const NiceViewException('图片下载超时，稍后再试');
    } on SocketException catch (error) {
      _log('body socket error: $error');
      throw const NiceViewException('图片下载中断，稍后再试');
    } on HttpException catch (error) {
      _log('body http error: $error');
      throw const NiceViewException('图片下载中断，稍后再试');
    }

    if (statusCode == 429) {
      await _rateLimiter.noteLockout();
      throw const ServerLockoutException('请求太快了，请稍后再试');
    }
    if (statusCode == 403) {
      await _rateLimiter.noteLockout();
      throw const ServerLockoutException('IP 已被封禁，请 30 分钟后再试');
    }
    if (statusCode == 404) {
      throw const ImageNotFoundException('图片不存在');
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw NiceViewException('服务器暂时不可用：$statusCode');
    }

    if (bytes.isEmpty) {
      throw const NiceViewException('图片数据为空');
    }

    if (contentType != null && !contentType.startsWith('image/')) {
      throw const EmptyTagException('该标签暂时没有图片');
    }

    return VeilImageResponse(
      bytes: bytes,
      contentType: contentType,
      imageId: int.tryParse(response.headers.value('x-image-id') ?? ''),
      galleryId: int.tryParse(response.headers.value('x-gallery-id') ?? ''),
    );
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[NiceView][VeilApi] $message');
    }
  }
}
