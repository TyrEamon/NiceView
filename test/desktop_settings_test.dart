import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/services/desktop_settings.dart';

void main() {
  test('normalizes proxy host, port, and blank download directory', () {
    final settings = const DesktopSettings(
      proxyEnabled: true,
      proxyHost: 'https://127.0.0.1:10808/path',
      proxyPort: 70000,
      downloadDirectory: '   ',
    ).normalized();

    expect(settings.proxyEnabled, isTrue);
    expect(settings.proxyHost, '127.0.0.1');
    expect(settings.proxyPort, DesktopSettings.defaultProxyPort);
    expect(settings.downloadDirectory, isNull);
    expect(settings.proxyRule, 'PROXY 127.0.0.1:10808');
  });

  test('removes wrapping quotes from custom download directory', () {
    final settings = const DesktopSettings(
      downloadDirectory: '"D:\\NiceView Downloads"',
    ).normalized();

    expect(settings.downloadDirectory, r'D:\NiceView Downloads');
  });
}
