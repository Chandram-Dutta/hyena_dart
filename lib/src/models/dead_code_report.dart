import 'code_entity.dart';

class DeadCodeReport {
  final List<CodeEntity> unusedEntities;
  final int totalDeclarations;
  final DateTime analyzedAt;

  DeadCodeReport({
    required this.unusedEntities,
    required this.totalDeclarations,
    DateTime? analyzedAt,
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

  Map<String, dynamic> toJson() => {
    'analyzedAt': analyzedAt.toIso8601String(),
    'summary': {
      'totalDeclarations': totalDeclarations,
      'unusedCount': unusedCount,
      'deadCodePercentage': deadCodePercentage.toStringAsFixed(2),
    },
    'unusedEntities': unusedEntities.map((e) => <String, dynamic>{
      'name': e.fullName,
      'type': e.typeLabel,
      'filePath': e.filePath,
      'line': e.line,
      'column': e.column,
      'isPublic': e.isPublic,
    }).toList(),
  };
}
