import '../../models/code_entity.dart';
import '../../models/dead_code_report.dart';
import 'symbols.dart';

/// Joins package graphs and reports declarations unreachable from live roots.
class DeadCodeReachability {
  const DeadCodeReachability();

  List<DeadCodeReport> buildReports(List<DeadCodeSymbols> analyses) {
    final referenceGraph = <String, Set<String>>{};
    final roots = <String>{};
    for (final analysis in analyses) {
      roots.addAll(analysis.rootElementKeys);
      for (final entry in analysis.referenceGraph.entries) {
        referenceGraph.putIfAbsent(entry.key, () => {}).addAll(entry.value);
      }
      for (final entry in analysis.elementKeyToEntity.entries) {
        final entity = entry.value;
        if ((analysis.config.ignoreExports && entity.isExported) ||
            (analysis.config.ignorePrivate && !entity.isPublic) ||
            analysis.unresolvedMemberNames.contains(entity.name)) {
          roots.add(entry.key);
        }
      }
    }

    final reachableElementKeys = _findReachableElements(referenceGraph, roots);
    return analyses.map((analysis) {
      final entityToKey = <CodeEntity, String>{};
      for (final entry in analysis.elementKeyToEntity.entries) {
        entityToKey[entry.value] = entry.key;
      }
      final unused = <CodeEntity>[];
      for (final entity in analysis.declarations) {
        if (_isUsed(
          entity,
          analysis.references,
          entityToKey,
          reachableElementKeys,
        )) {
          continue;
        }
        if (analysis.config.ignoreExports && entity.isExported) continue;
        if (!entity.isPublic && analysis.config.ignorePrivate) continue;
        unused.add(entity);
      }
      return DeadCodeReport(
        unusedEntities: unused,
        totalDeclarations: analysis.declarations.length,
      );
    }).toList();
  }

  Set<String> _findReachableElements(
    Map<String, Set<String>> referenceGraph,
    Set<String> roots,
  ) {
    final reachable = <String>{...roots};
    final pending = roots.toList();
    while (pending.isNotEmpty) {
      final source = pending.removeLast();
      for (final target in referenceGraph[source] ?? const <String>{}) {
        if (reachable.add(target)) pending.add(target);
      }
    }
    return reachable;
  }

  bool _isUsed(
    CodeEntity entity,
    Set<String> references,
    Map<CodeEntity, String> entityToKey,
    Set<String> reachableElementKeys,
  ) {
    final key = entityToKey[entity];
    if (key != null) {
      return reachableElementKeys.contains(key);
    }

    if (references.contains(entity.name)) return true;
    if (references.contains(entity.fullName)) return true;

    if (entity.type == EntityType.classDecl ||
        entity.type == EntityType.abstractClass ||
        entity.type == EntityType.enum_) {
      for (final ref in references) {
        if (ref.startsWith('${entity.name}.')) return true;
      }
    }

    return false;
  }
}
