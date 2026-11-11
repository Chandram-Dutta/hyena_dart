import 'analysis_path.dart';
import 'code_entity.dart';
import 'skipped_file.dart';

class DeadCodeReport {
  final List<CodeEntity> unusedEntities;
  final int totalDeclarations;
  final DateTime analyzedAt;

  /// Files that could not be analyzed and were left out of this report.
  ///
  /// Declarations in these files are not reported. Code they reference is
  /// treated as used wherever the analyzer could still determine it.
  final List<SkippedFile> skippedFiles;

  DeadCodeReport({
    required this.unusedEntities,
    required this.totalDeclarations,
    DateTime? analyzedAt,
    this.skippedFiles = const [],
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  int get unusedCount => unusedEntities.length;

  double get deadCodePercentage =>
      totalDeclarations > 0 ? (unusedCount / totalDeclarations) * 100 : 0;

  Map<EntityType, List<CodeEntity>> get groupedByType {
    final map = <EntityType, List<CodeEntity>>{};
    for (final entity in unusedEntities) {
      map.putIfAbsent(entity.type, () => []).add(entity);
    }
    return map;
  }

  Map<String, List<CodeEntity>> get groupedByFile {
    final map = <String, List<CodeEntity>>{};
    for (final entity in unusedEntities) {
      map.putIfAbsent(entity.filePath, () => []).add(entity);
    }
    return map;
  }

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
