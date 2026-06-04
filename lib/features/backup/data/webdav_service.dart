import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exceptions.dart';
import '../domain/webdav_backup_file.dart';
import '../domain/webdav_config.dart';

final webDavServiceProvider = Provider<WebDavService>((ref) {
  return WebDavService();
});

class WebDavService {
  WebDavService() : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 30);
    _client.idleTimeout = const Duration(seconds: 15);
  }

  static const _timeout = Duration(seconds: 45);

  final HttpClient _client;

  Future<void> testConnection(WebDavConfig config) async {
    _ensureConfigured(config);
    await _ensureRemoteDirectory(config);
  }

  Future<String> uploadBackup({
    required WebDavConfig config,
    required String fileName,
    required Uint8List bytes,
  }) async {
    _ensureConfigured(config);
    await _ensureRemoteDirectory(config);
    final uri = _fileUri(config, fileName);
    final response = await _send(
      'PUT',
      uri,
      config,
      body: bytes,
      headers: const {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
    );
    await _discard(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NiceViewException('WebDAV 上传失败：HTTP ${response.statusCode}');
    }
    return uri.toString();
  }

  Future<List<WebDavBackupFile>> listBackups(WebDavConfig config) async {
    _ensureConfigured(config);
    final uri = _directoryUri(config);
    final response = await _send(
      'PROPFIND',
      uri,
      config,
      headers: const {
        'Depth': '1',
        HttpHeaders.contentTypeHeader: 'application/xml; charset=utf-8',
      },
      body: Uint8List.fromList(utf8.encode('''
<?xml version="1.0" encoding="utf-8" ?>
<propfind xmlns="DAV:">
  <prop>
    <getcontentlength />
    <getlastmodified />
    <resourcetype />
  </prop>
</propfind>
''')),
    );
    final bytes = await _readBytes(response);
    if (response.statusCode == 404) {
      return const <WebDavBackupFile>[];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NiceViewException('WebDAV 列表读取失败：HTTP ${response.statusCode}');
    }

    try {
      final directoryPath = _directoryUri(config).path;
      final files = <WebDavBackupFile>[];
      for (final responseXml in _responseBlocks(utf8.decode(bytes))) {
        final href = _tagText(responseXml, 'href')?.trim();
        if (href == null || href.isEmpty) {
          continue;
        }
        final decodedPath = _hrefPath(href, uri);
        final isDirectory = RegExp(
          r'<(?:\w+:)?collection\b',
          caseSensitive: false,
        ).hasMatch(responseXml);
        if (isDirectory || decodedPath == directoryPath) {
          continue;
        }
        final name = decodedPath
            .split('/')
            .where((part) => part.isNotEmpty)
            .last;
        if (!name.toLowerCase().endsWith('.json')) {
          continue;
        }
        files.add(WebDavBackupFile(
          name: name,
          path: decodedPath,
          updatedAt: _tryParseHttpDate(
            _tagText(responseXml, 'getlastmodified')?.trim(),
          ),
          size: int.tryParse(
            _tagText(responseXml, 'getcontentlength')?.trim() ?? '',
          ),
        ));
      }
      files.sort((a, b) {
        final aTime = a.updatedAt;
        final bTime = b.updatedAt;
        if (aTime == null && bTime == null) {
          return b.name.compareTo(a.name);
        }
        if (aTime == null) {
          return 1;
        }
        if (bTime == null) {
          return -1;
        }
        return bTime.compareTo(aTime);
      });
      return files;
    } on FormatException catch (error) {
      throw NiceViewException('WebDAV 列表解析失败：${error.message}');
    }
  }

  Future<Uint8List> downloadBackup({
    required WebDavConfig config,
    required WebDavBackupFile file,
  }) async {
    _ensureConfigured(config);
    final uri = _pathUri(config, file.path);
    final response = await _send('GET', uri, config);
    final bytes = await _readBytes(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NiceViewException('WebDAV 下载失败：HTTP ${response.statusCode}');
    }
    if (bytes.isEmpty) {
      throw const NiceViewException('WebDAV 备份文件为空');
    }
    return bytes;
  }

  Future<void> _ensureRemoteDirectory(WebDavConfig config) async {
    final uri = _directoryUri(config);
    final response = await _send('MKCOL', uri, config);
    await _discard(response);
    if (response.statusCode == 201 || response.statusCode == 405) {
      return;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw NiceViewException('WebDAV 目录不可用：HTTP ${response.statusCode}');
  }

  Future<HttpClientResponse> _send(
    String method,
    Uri uri,
    WebDavConfig config, {
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(_timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, _basicAuth(config))
        ..set(HttpHeaders.userAgentHeader, 'NiceView/1.0');
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      return request.close().timeout(_timeout);
    } on TimeoutException {
      throw const NiceViewException('WebDAV 连接超时');
    } on SocketException {
      throw const NiceViewException('WebDAV 网络连接失败');
    } on HandshakeException {
      throw const NiceViewException('WebDAV 安全连接失败');
    } on HttpException catch (error) {
      throw NiceViewException(error.message);
    }
  }

  Future<Uint8List> _readBytes(HttpClientResponse response) async {
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw const NiceViewException('WebDAV 响应超时');
    } on SocketException {
      throw const NiceViewException('WebDAV 响应中断');
    } on HttpException catch (error) {
      throw NiceViewException(error.message);
    }
  }

  Future<void> _discard(HttpClientResponse response) async {
    await _readBytes(response);
  }

  Uri _directoryUri(WebDavConfig config) {
    final base = _baseUri(config);
    return base.replace(
      path: _joinPaths(base.path, config.normalizedRemotePath),
      query: '',
      fragment: '',
    );
  }

  Uri _fileUri(WebDavConfig config, String fileName) {
    final directory = _directoryUri(config);
    return directory.replace(
      path: _joinPaths(directory.path, fileName),
      query: '',
      fragment: '',
    );
  }

  Uri _pathUri(WebDavConfig config, String path) {
    final base = _baseUri(config);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return base.replace(path: normalizedPath, query: '', fragment: '');
  }

  Uri _baseUri(WebDavConfig config) {
    final uri = Uri.tryParse(config.baseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const NiceViewException('WebDAV 地址格式不正确');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const NiceViewException('WebDAV 地址只支持 HTTP/HTTPS');
    }
    return uri;
  }

  String _joinPaths(String first, String second) {
    final normalizedFirst = first.endsWith('/') ? first : '$first/';
    final normalizedSecond =
        second.startsWith('/') ? second.substring(1) : second;
    return Uri(path: '$normalizedFirst$normalizedSecond').path;
  }

  String _hrefPath(String href, Uri directoryUri) {
    final path = Uri.decodeComponent(Uri.parse(href).path);
    if (path.startsWith('/')) {
      return path;
    }
    return _joinPaths(directoryUri.path, path);
  }

  String _basicAuth(WebDavConfig config) {
    final token = base64Encode(
      utf8.encode('${config.username}:${config.password}'),
    );
    return 'Basic $token';
  }

  Iterable<String> _responseBlocks(String xml) sync* {
    final pattern = RegExp(
      r'<(?:\w+:)?response\b[^>]*>[\s\S]*?<\/(?:\w+:)?response>',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      yield match.group(0)!;
    }
  }

  String? _tagText(String xml, String name) {
    final pattern = RegExp(
      '<(?:\\w+:)?$name\\b[^>]*>([\\s\\S]*?)<\\/(?:\\w+:)?$name>',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(xml);
    if (match == null) {
      return null;
    }
    return match.group(1)
        ?.replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  DateTime? _tryParseHttpDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return HttpDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  void _ensureConfigured(WebDavConfig config) {
    if (!config.isConfigured) {
      throw const NiceViewException('请先填写 WebDAV 配置');
    }
  }
}
