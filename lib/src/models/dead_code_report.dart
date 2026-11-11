import 'analysis_path.dart';
import 'code_entity.dart';
import 'skipped_file.dart';

/// The result of a dead code analysis.
class DeadCodeReport {
  /// Declarations that were found to be unused.
  final List<CodeEntity> unusedEntities;

  /// Number of declarations that were considered.
  final int totalDeclarations;

  /// When the analysis was performed.
  final DateTime analyzedAt;

  /// Files that could not be analyzed and were left out of this report.
  ///
  /// Declarations in these files are not reported. Code they reference is
  /// treated as used wherever the analyzer could still determine it.
  final List<SkippedFile> skippedFiles;

  /// Creates a dead code report.
  ///
  /// [analyzedAt] defaults to the current time.
  DeadCodeReport({
    required this.unusedEntities,
    required this.totalDeclarations,
    DateTime? analyzedAt,
    this.skippedFiles = const [],
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  /// Number of unused declarations.
  int get unusedCount => unusedEntities.length;

  /// Unused declarations as a percentage of [totalDeclarations].
  double get deadCodePercentage =>
      totalDeclarations > 0 ? (unusedCount / totalDeclarations) * 100 : 0;

  /// [unusedEntities] grouped by [CodeEntity.type].
  Map<EntityType, List<CodeEntity>> get groupedByType {
    final map = <EntityType, List<CodeEntity>>{};
    for (final entity in unusedEntities) {
      map.putIfAbsent(entity.type, () => []).add(entity);
    }
    return map;
  }

  /// [unusedEntities] grouped by [CodeEntity.filePath].
  Map<String, List<CodeEntity>> get groupedByFile {
    final map = <String, List<CodeEntity>>{};
    for (final entity in unusedEntities) {
      map.putIfAbsent(entity.filePath, () => []).add(entity);
    }
    return map;
  }

  /// Serializes this report, including a summary section, to JSON.
  ///
  /// When [rootPath] is given, file paths are emitted relative to it.
  Map<String, dynamic> toJson({String? rootPath}) => {
    'analyzedAt': analyzedAt.toIso8601String(),
    'summary': {
      'totalDeclarations': totalDeclarations,
      'unusedCount': unusedCount,
      'deadCodePercentage': deadCodePercentage.toStringAsFixed(2),
    },
    'unusedEntities': unusedEntities
        .map(
          (e) => <String, dynamic>{
            'name': e.fullName,
            'type': e.typeLabel,
            'filePath': rootPath == null
                ? e.filePath
                : relativeAnalysisPath(e.filePath, rootPath),
            'line': e.line,
            'column': e.column,
            'isPublic': e.isPublic,
          },
        )
        .toList(),
    'skippedFiles': skippedFiles
        .map((file) => file.toJson(rootPath: rootPath))
        .toList(),
  };
}
