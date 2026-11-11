import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Options that control dead code and complexity analysis.
///
/// Construct one directly, or use [load] to read the `hyena:` section of a
/// `hyena.yaml` or `analysis_options.yaml` file. Every option has a
/// conservative default.
class AnalyzerConfig {
  /// Glob patterns for files to skip (`hyena.exclude`), matched against both
  /// relative and absolute paths, such as `**/*.g.dart`.
  final List<String> excludePatterns;

  /// Functions with a cyclomatic complexity above this value are reported
  /// (`hyena.complexity.cyclomatic_threshold`, default 20).
  final int cyclomaticThreshold;

  /// Functions nested deeper than this value are reported
  /// (`hyena.complexity.max_nesting`, default 5).
  final int maxNestingLevel;

  /// Functions with more parameters than this value are reported
  /// (`hyena.complexity.max_parameters`, default 6).
  final int maxParameters;

  /// Whether `main` functions are treated as used
  /// (`hyena.dead_code.ignore_main`, default `true`).
  final bool ignoreMain;

  /// Whether declarations reachable through a public library export are
  /// treated as used (`hyena.dead_code.ignore_exports`, default `false`).
  ///
  /// Enable this for reusable packages whose public API has no caller inside
  /// the repository.
  final bool ignoreExports;

  /// Whether private (`_`-prefixed) declarations are left out of dead code
  /// results (`hyena.dead_code.ignore_private`, default `false`).
  final bool ignorePrivate;

  /// Declaration names, either `name` or `Parent.name`, that are always
  /// treated as used (`hyena.dead_code.entry_points`).
  final List<String> entryPoints;

  /// Annotation names (with or without a leading `@`) whose annotated
  /// declarations are treated as used
  /// (`hyena.dead_code.entry_point_annotations`).
  final List<String> entryPointAnnotations;

  /// Creates a configuration. Omitted options use their defaults.
  AnalyzerConfig({
    this.excludePatterns = const [],
    this.cyclomaticThreshold = 20,
    this.maxNestingLevel = 5,
    this.maxParameters = 6,
    this.ignoreMain = true,
    this.ignoreExports = false,
    this.ignorePrivate = false,
    this.entryPoints = const [],
    this.entryPointAnnotations = const [],
  });

  /// Loads configuration from a YAML file.
  ///
  /// If [configPath] is given, that file is read. Otherwise, the search
  /// starts at [targetPath] (or the current directory) and walks up to the
  /// first directory that contains `hyena.yaml` or `analysis_options.yaml`.
  /// Options are read from that file's `hyena:` section. If no file or
  /// section is found, the defaults are returned.
  ///
  /// When [searchBoundary] is set, both the search and the resolved config
  /// file must stay inside that directory.
  ///
  /// Throws an [ArgumentError] for a missing file or a boundary violation,
  /// and a [FormatException] for invalid configuration.
  static Future<AnalyzerConfig> load(
    String? configPath, {
    String? targetPath,
    String? searchBoundary,
  }) async {
    final boundary = searchBoundary == null
        ? null
        : await _resolveBoundary(searchBoundary);
    if (configPath != null) {
      final file = File(configPath);
      if (!await file.exists()) {
        throw ArgumentError('Configuration file does not exist: $configPath');
      }
      final safeFile = await _resolveConfigFile(file, boundary);
      return _parseConfig(await safeFile.readAsString(), safeFile.path);
    }

    final file = await _findConfigFile(
      targetPath ?? Directory.current.path,
      searchBoundary: boundary,
    );
    if (file != null) {
      return _parseConfig(await file.readAsString(), file.path);
    }
    return AnalyzerConfig();
  }

  static Future<String> _resolveBoundary(String searchBoundary) async {
    final directory = Directory(p.absolute(searchBoundary));
    if (!await directory.exists()) {
      throw ArgumentError(
        'Configuration search boundary does not exist: $searchBoundary',
      );
    }
    return p.normalize(await directory.resolveSymbolicLinks());
  }

  static Future<File> _resolveConfigFile(
    File file,
    String? searchBoundary,
  ) async {
    if (searchBoundary == null) return file;

    final resolvedPath = p.normalize(await file.resolveSymbolicLinks());
    if (!_isWithinOrEqual(searchBoundary, resolvedPath)) {
      throw ArgumentError('Configuration file is outside the search boundary');
    }
    return File(resolvedPath);
  }

  static Future<File?> _findConfigFile(
    String targetPath, {
    String? searchBoundary,
  }) async {
    final absoluteTarget = p.absolute(targetPath);
    var directory = await FileSystemEntity.isFile(absoluteTarget)
        ? File(absoluteTarget).parent
        : Directory(absoluteTarget);
    if (searchBoundary != null && await directory.exists()) {
      directory = Directory(
        p.normalize(await directory.resolveSymbolicLinks()),
      );
    }

    if (searchBoundary != null &&
        !_isWithinOrEqual(searchBoundary, p.normalize(directory.path))) {
      throw ArgumentError(
        'Configuration target is outside the search boundary',
      );
    }

    while (true) {
      for (final name in ['hyena.yaml', 'analysis_options.yaml']) {
        final file = File(p.join(directory.path, name));
        if (await file.exists()) {
          return _resolveConfigFile(file, searchBoundary);
        }
      }
      if (searchBoundary != null &&
          p.equals(p.normalize(directory.path), searchBoundary)) {
        return null;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  static bool _isWithinOrEqual(String rootPath, String candidatePath) =>
      p.equals(rootPath, candidatePath) || p.isWithin(rootPath, candidatePath);

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
      final entryPoints = _stringList(
        deadCode?['entry_points'],
        'hyena.dead_code.entry_points',
      );
      final entryPointAnnotations = _stringList(
        deadCode?['entry_point_annotations'],
        'hyena.dead_code.entry_point_annotations',
        stripLeadingAt: true,
      );

      final config = AnalyzerConfig(
        excludePatterns: excludePatterns,
        cyclomaticThreshold: complexity?['cyclomatic_threshold'] as int? ?? 20,
        maxNestingLevel: complexity?['max_nesting'] as int? ?? 5,
        maxParameters: complexity?['max_parameters'] as int? ?? 6,
        ignoreMain: deadCode?['ignore_main'] as bool? ?? true,
        ignoreExports: deadCode?['ignore_exports'] as bool? ?? false,
        ignorePrivate: deadCode?['ignore_private'] as bool? ?? false,
        entryPoints: entryPoints,
        entryPointAnnotations: entryPointAnnotations,
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

  static List<String> _stringList(
    Object? value,
    String fieldName, {
    bool stripLeadingAt = false,
  }) {
    if (value == null) return const [];
    if (value is! YamlList) {
      throw FormatException('$fieldName must be a list');
    }
    return value.map((entry) {
      if (entry is! String) {
        throw FormatException('$fieldName entries must be strings');
      }
      var normalized = entry.trim();
      if (stripLeadingAt && normalized.startsWith('@')) {
        normalized = normalized.substring(1);
      }
      if (normalized.isEmpty) {
        throw FormatException('$fieldName entries cannot be empty');
      }
      return normalized;
    }).toList();
  }

  /// Returns a copy of this configuration with the given options replaced.
  AnalyzerConfig copyWith({
    List<String>? excludePatterns,
    int? cyclomaticThreshold,
    int? maxNestingLevel,
    int? maxParameters,
    bool? ignoreMain,
    bool? ignoreExports,
    bool? ignorePrivate,
    List<String>? entryPoints,
    List<String>? entryPointAnnotations,
  }) {
    return AnalyzerConfig(
      excludePatterns: excludePatterns ?? this.excludePatterns,
      cyclomaticThreshold: cyclomaticThreshold ?? this.cyclomaticThreshold,
      maxNestingLevel: maxNestingLevel ?? this.maxNestingLevel,
      maxParameters: maxParameters ?? this.maxParameters,
      ignoreMain: ignoreMain ?? this.ignoreMain,
      ignoreExports: ignoreExports ?? this.ignoreExports,
      ignorePrivate: ignorePrivate ?? this.ignorePrivate,
      entryPoints: entryPoints ?? this.entryPoints,
      entryPointAnnotations:
          entryPointAnnotations ?? this.entryPointAnnotations,
    );
  }
}
