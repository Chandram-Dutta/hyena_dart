import 'dart:io';

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

  static Future<AnalyzerConfig> load(String? configPath) async {
    final paths = [
      configPath,
      'hyena.yaml',
      'analysis_options.yaml',
    ].whereType<String>();

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        return _parseConfig(await file.readAsString());
      }
    }

    return AnalyzerConfig();
  }

  static AnalyzerConfig _parseConfig(String content) {
    try {
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null) return AnalyzerConfig();

      final hyena = yaml['hyena'] as YamlMap?;
      if (hyena == null) return AnalyzerConfig();

      final excludePatterns = <String>[];
      final exclude = hyena['exclude'];
      if (exclude is YamlList) {
        for (final pattern in exclude) {
          if (pattern is String) {
            excludePatterns.add(pattern);
          }
        }
      }

      final complexity = hyena['complexity'] as YamlMap?;
      final deadCode = hyena['dead_code'] as YamlMap?;

      return AnalyzerConfig(
        excludePatterns: excludePatterns,
        cyclomaticThreshold: complexity?['cyclomatic_threshold'] as int? ?? 20,
        maxNestingLevel: complexity?['max_nesting'] as int? ?? 5,
        maxParameters: complexity?['max_parameters'] as int? ?? 6,
        ignoreMain: deadCode?['ignore_main'] as bool? ?? true,
        ignoreExports: deadCode?['ignore_exports'] as bool? ?? true,
        ignorePrivate: deadCode?['ignore_private'] as bool? ?? false,
      );
    } catch (e) {
      return AnalyzerConfig();
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
