import '../../config/analyzer_config.dart';
import '../../models/code_entity.dart';

/// Symbols and references collected for one package before workspace reachability.
class DeadCodeSymbols {
  final AnalyzerConfig config;
  final List<CodeEntity> declarations;
  final Set<String> references;
  final Map<String, CodeEntity> elementKeyToEntity;
  final Map<String, Set<String>> referenceGraph;
  final Set<String> rootElementKeys;
  final Set<String> unresolvedMemberNames;
  final Duration duration;

  const DeadCodeSymbols({
    required this.config,
    required this.declarations,
    required this.references,
    required this.elementKeyToEntity,
    required this.referenceGraph,
    required this.rootElementKeys,
    required this.unresolvedMemberNames,
    required this.duration,
  });
}
