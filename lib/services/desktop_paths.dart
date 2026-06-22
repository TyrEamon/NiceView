import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> getNiceViewDesktopOutputDirectory() async {
  final downloadsDirectory = await getDownloadsDirectory();
  final baseDirectory =
      downloadsDirectory ?? await getApplicationDocumentsDirectory();
  final outputDirectory = Directory(p.join(baseDirectory.path, 'NiceView'));
  await outputDirectory.create(recursive: true);
  return outputDirectory;
}
