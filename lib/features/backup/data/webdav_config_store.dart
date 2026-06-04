import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/shared_preferences_provider.dart';
import '../domain/webdav_config.dart';

final webDavConfigStoreProvider = Provider<WebDavConfigStore>((ref) {
  return WebDavConfigStore(ref.watch(sharedPreferencesProvider));
});

class WebDavConfigStore {
  const WebDavConfigStore(this._preferences);

  static const _baseUrlKey = 'nice_view.webdav.base_url';
  static const _usernameKey = 'nice_view.webdav.username';
  static const _passwordKey = 'nice_view.webdav.password';
  static const _remotePathKey = 'nice_view.webdav.remote_path';

  final SharedPreferences _preferences;

  WebDavConfig load() {
    return WebDavConfig(
      baseUrl: _preferences.getString(_baseUrlKey) ?? '',
      username: _preferences.getString(_usernameKey) ?? '',
      password: _preferences.getString(_passwordKey) ?? '',
      remotePath: _preferences.getString(_remotePathKey) ?? '/NiceView/',
    );
  }

  Future<void> save(WebDavConfig config) async {
    await _preferences.setString(_baseUrlKey, config.baseUrl.trim());
    await _preferences.setString(_usernameKey, config.username.trim());
    await _preferences.setString(_passwordKey, config.password);
    await _preferences.setString(
      _remotePathKey,
      config.normalizedRemotePath,
    );
  }
}
