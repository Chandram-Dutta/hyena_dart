import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the nearest directory at or above [targetPath] that contains a
/// `pubspec.yaml`, or the target's own directory if there is none.
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

/// Returns [path] relative to [rootPath], using `/` as the separator.
String relativeAnalysisPath(String path, String rootPath) {
  final relative = p.relative(p.absolute(path), from: p.absolute(rootPath));
  return p.posix.joinAll(p.split(relative));
}

/// Returns the path used in findings; the same as [relativeAnalysisPath].
String relativeFindingPath(String filePath, String rootPath) =>
    relativeAnalysisPath(filePath, rootPath);
