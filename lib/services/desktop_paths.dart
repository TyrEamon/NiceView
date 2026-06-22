import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> getNiceViewDesktopOutputDirectory({
  String? customDirectory,
}) async {
  final configuredDirectory = customDirectory?.trim();
  if (configuredDirectory != null && configuredDirectory.isNotEmpty) {
    final outputDirectory = Directory(configuredDirectory);
    await outputDirectory.create(recursive: true);
    return outputDirectory;
  }

  final downloadsDirectory = await getDownloadsDirectory();
  final baseDirectory =
      downloadsDirectory ?? await getApplicationDocumentsDirectory();
  final outputDirectory = Directory(p.join(baseDirectory.path, 'NiceView'));
  await outputDirectory.create(recursive: true);
  return outputDirectory;
}
