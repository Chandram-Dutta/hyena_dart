import 'dart:io';

import 'package:path/path.dart' as p;

String analysisRootForTarget(String targetPath) {
  final absoluteTarget = p.absolute(targetPath);
  var directory = FileSystemEntity.isFileSync(absoluteTarget)
      ? File(absoluteTarget).parent
      : Directory(absoluteTarget);
  final fallbackRoot = directory.path;
  while (true) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      return p.normalize(directory.path);
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return p.normalize(fallbackRoot);
    directory = parent;
  }
}

String relativeAnalysisPath(String path, String rootPath) {
  final relative = p.relative(p.absolute(path), from: p.absolute(rootPath));
  return p.posix.joinAll(p.split(relative));
}

String relativeFindingPath(String filePath, String rootPath) =>
    relativeAnalysisPath(filePath, rootPath);
