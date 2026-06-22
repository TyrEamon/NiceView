import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

final desktopSettingsProvider =
    StateNotifierProvider<DesktopSettingsController, DesktopSettings>((ref) {
  return DesktopSettingsController(ref.watch(sharedPreferencesProvider));
});

class DesktopSettings {
  const DesktopSettings({
    this.proxyEnabled = false,
    this.proxyHost = defaultProxyHost,
    this.proxyPort = defaultProxyPort,
    this.downloadDirectory,
  });

  static const defaultProxyHost = '127.0.0.1';
  static const defaultProxyPort = 10808;

  final bool proxyEnabled;
  final String proxyHost;
  final int proxyPort;
  final String? downloadDirectory;

  bool get hasProxy =>
      proxyEnabled && proxyHost.trim().isNotEmpty && _isValidPort(proxyPort);

  String get proxyRule => 'PROXY ${proxyHost.trim()}:$proxyPort';

  DesktopSettings normalized() {
    final host = _normalizeProxyHost(proxyHost);
    return DesktopSettings(
      proxyEnabled: proxyEnabled,
      proxyHost: host.isEmpty ? defaultProxyHost : host,
      proxyPort: _isValidPort(proxyPort) ? proxyPort : defaultProxyPort,
      downloadDirectory: _normalizeOptionalPath(downloadDirectory),
    );
  }

  DesktopSettings copyWith({
    bool? proxyEnabled,
    String? proxyHost,
    int? proxyPort,
    Object? downloadDirectory = _unset,
  }) {
    return DesktopSettings(
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      downloadDirectory: identical(downloadDirectory, _unset)
          ? this.downloadDirectory
          : downloadDirectory as String?,
    );
  }

  static bool _isValidPort(int port) => port > 0 && port <= 65535;

  static String _normalizeProxyHost(String value) {
    var host = value.trim();
    for (final prefix in const [
      'http://',
      'https://',
      'socks://',
      'socks5://',
    ]) {
      if (host.toLowerCase().startsWith(prefix)) {
        host = host.substring(prefix.length);
        break;
      }
    }
    final slashIndex = host.indexOf('/');
    if (slashIndex >= 0) {
      host = host.substring(0, slashIndex);
    }
    if (!host.startsWith('[')) {
      final colonIndex = host.indexOf(':');
      if (colonIndex >= 0) {
        host = host.substring(0, colonIndex);
      }
    }
    return host.trim();
  }

  static String? _normalizeOptionalPath(String? value) {
    var path = value?.trim() ?? '';
    if (path.length >= 2 &&
        ((path.startsWith('"') && path.endsWith('"')) ||
            (path.startsWith("'") && path.endsWith("'")))) {
      path = path.substring(1, path.length - 1).trim();
    }
    return path.isEmpty ? null : path;
  }
}

class DesktopSettingsController extends StateNotifier<DesktopSettings> {
  DesktopSettingsController(this._preferences) : super(_load(_preferences));

  static const _proxyEnabledKey = 'desktop.proxy.enabled';
  static const _proxyHostKey = 'desktop.proxy.host';
  static const _proxyPortKey = 'desktop.proxy.port';
  static const _downloadDirectoryKey = 'desktop.download.directory';

  final SharedPreferences _preferences;

  Future<void> save(DesktopSettings settings) async {
    final normalized = settings.normalized();
    state = normalized;
    await _preferences.setBool(_proxyEnabledKey, normalized.proxyEnabled);
    await _preferences.setString(_proxyHostKey, normalized.proxyHost);
    await _preferences.setInt(_proxyPortKey, normalized.proxyPort);
    final downloadDirectory = normalized.downloadDirectory;
    if (downloadDirectory == null) {
      await _preferences.remove(_downloadDirectoryKey);
    } else {
      await _preferences.setString(_downloadDirectoryKey, downloadDirectory);
    }
  }

  static DesktopSettings _load(SharedPreferences preferences) {
    return DesktopSettings(
      proxyEnabled: preferences.getBool(_proxyEnabledKey) ?? false,
      proxyHost:
          preferences.getString(_proxyHostKey) ?? DesktopSettings.defaultProxyHost,
      proxyPort:
          preferences.getInt(_proxyPortKey) ?? DesktopSettings.defaultProxyPort,
      downloadDirectory: preferences.getString(_downloadDirectoryKey),
    ).normalized();
  }
}

const _unset = Object();
