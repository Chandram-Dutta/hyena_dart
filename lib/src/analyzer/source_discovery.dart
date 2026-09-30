import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';

/// Shared Dart source enumeration and exclusion policy for both analyzers.
class SourceDiscovery {
  final AnalyzerConfig config;

  const SourceDiscovery(this.config);

  Future<List<String>> collect(String targetPath) async {
    final file = File(targetPath);
    if (await file.exists()) {
      if (!file.path.endsWith('.dart')) {
        throw ArgumentError('Target file is not a Dart source: $targetPath');
      }
      return [file.path];
    }

    final target = Directory(targetPath);
    if (!await target.exists()) {
      throw ArgumentError('Target path does not exist: $targetPath');
    }

    final glob = Glob('**.dart');
    final files = <String>[];

    await for (final entity in glob.list(root: targetPath)) {
      if (entity is File) {
        files.add(entity.path);
      }
    }

    return files;
  }

  bool shouldExclude(
    String filePath, {
    required String analysisRoot,
    required List<String> excludedPaths,
  }) {
    final normalizedPath = p.normalize(p.absolute(filePath));
    if (excludedPaths.any(
      (root) =>
          p.equals(root, normalizedPath) || p.isWithin(root, normalizedPath),
    )) {
      return true;
    }
    final relativePath = p.posix.joinAll(
      p.split(p.relative(normalizedPath, from: analysisRoot)),
    );
    final absolutePath = p.posix.joinAll(p.split(normalizedPath));

    for (final pattern in config.excludePatterns) {
      final glob = Glob(pattern);
      if (glob.matches(relativePath) || glob.matches(absolutePath)) {
        return true;
      }
    }

    if (normalizedPath.endsWith('.g.dart') ||
        normalizedPath.endsWith('.freezed.dart') ||
        normalizedPath.endsWith('.mocks.dart')) {
      return true;
    }

    final segments = p.split(normalizedPath);
    if (segments.contains('.dart_tool') ||
        segments.contains('build') ||
        segments.contains('generated')) {
      return true;
    }

    return false;
  }
}
