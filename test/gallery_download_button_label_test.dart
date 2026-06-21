import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/features/random_image/presentation/widgets/side_info_drawer.dart';

void main() {
  test('parses image count hints from gallery titles', () {
    expect(
      galleryDownloadButtonLabel('AmourAngels Presenting - Velana (53P)'),
      '下载整包 (53P)',
    );
    expect(
      galleryDownloadButtonLabel('Fantia 2025 Part01 (62P - 3V)'),
      '下载整包 (62P)',
    );
    expect(
      galleryDownloadButtonLabel('Fantia 2025 Part01 (62P – 3V)'),
      '下载整包 (62P)',
    );
    expect(galleryDownloadButtonLabel('No count title'), '下载整包');
  });
}
