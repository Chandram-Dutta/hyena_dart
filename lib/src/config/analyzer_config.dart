import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class AnalyzerConfig {
  final List<String> excludePatterns;
  final int cyclomaticThreshold;
  final int maxNestingLevel;
  final int maxParameters;
  final bool ignoreMain;
  final bool ignoreExports;
  final bool ignorePrivate;

  AnalyzerConfig({
    this.excludePatterns = const [],
    this.cyclomaticThreshold = 20,
    this.maxNestingLevel = 5,
    this.maxParameters = 6,
    this.ignoreMain = true,
    this.ignoreExports = true,
    this.ignorePrivate = false,
  });

  static Future<AnalyzerConfig> load(
    String? configPath, {
    String? targetPath,
  }) async {
    if (configPath != null) {
      final file = File(configPath);
      if (!await file.exists()) {
        throw ArgumentError('Configuration file does not exist: $configPath');
      }
      return _parseConfig(await file.readAsString(), file.path);
    }

    final file = await _findConfigFile(targetPath ?? Directory.current.path);
    if (file != null) {
      return _parseConfig(await file.readAsString(), file.path);
    }
    return AnalyzerConfig();
  }

  static Future<File?> _findConfigFile(String targetPath) async {
    final absoluteTarget = p.absolute(targetPath);
    var directory = await FileSystemEntity.isFile(absoluteTarget)
        ? File(absoluteTarget).parent
        : Directory(absoluteTarget);

    while (true) {
      for (final name in ['hyena.yaml', 'analysis_options.yaml']) {
        final file = File(p.join(directory.path, name));
        if (await file.exists()) return file;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  static AnalyzerConfig _parseConfig(String content, String sourcePath) {
    try {
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null) return AnalyzerConfig();

      final hyena = yaml['hyena'] as YamlMap?;
      if (hyena == null) return AnalyzerConfig();

      final excludePatterns = <String>[];
      final exclude = hyena['exclude'];
      if (exclude != null && exclude is! YamlList) {
        throw const FormatException('hyena.exclude must be a list');
      }
      if (exclude is YamlList) {
        for (final pattern in exclude) {
          if (pattern is! String) {
            throw const FormatException(
              'hyena.exclude entries must be strings',
            );
          }
          excludePatterns.add(pattern);
        }
      }

      final complexity = hyena['complexity'] as YamlMap?;
      final deadCode = hyena['dead_code'] as YamlMap?;

      final config = AnalyzerConfig(
        excludePatterns: excludePatterns,
        cyclomaticThreshold: complexity?['cyclomatic_threshold'] as int? ?? 20,
        maxNestingLevel: complexity?['max_nesting'] as int? ?? 5,
        maxParameters: complexity?['max_parameters'] as int? ?? 6,
        ignoreMain: deadCode?['ignore_main'] as bool? ?? true,
        ignoreExports: deadCode?['ignore_exports'] as bool? ?? true,
        ignorePrivate: deadCode?['ignore_private'] as bool? ?? false,
      );
      if (config.cyclomaticThreshold < 0 ||
          config.maxNestingLevel < 0 ||
          config.maxParameters < 0) {
        throw const FormatException('complexity thresholds cannot be negative');
      }
      return config;
    } catch (error) {
      throw FormatException(
        'Invalid Hyena configuration in $sourcePath: $error',
      );
    }
  }

  AnalyzerConfig copyWith({
    List<String>? excludePatterns,
    int? cyclomaticThreshold,
    int? maxNestingLevel,
    int? maxParameters,
    bool? ignoreMain,
    bool? ignoreExports,
    bool? ignorePrivate,
  }) {
    return AnalyzerConfig(
      excludePatterns: excludePatterns ?? this.excludePatterns,
      cyclomaticThreshold: cyclomaticThreshold ?? this.cyclomaticThreshold,
      maxNestingLevel: maxNestingLevel ?? this.maxNestingLevel,
      maxParameters: maxParameters ?? this.maxParameters,
      ignoreMain: ignoreMain ?? this.ignoreMain,
      ignoreExports: ignoreExports ?? this.ignoreExports,
      ignorePrivate: ignorePrivate ?? this.ignorePrivate,
    );
  }
}
