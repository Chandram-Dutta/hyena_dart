import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../config/analyzer_config.dart';
import '../../models/code_entity.dart';
import '../ast_visitors/declaration_visitor.dart';
import '../ast_visitors/reference_visitor.dart';
import '../source_discovery.dart';
import 'library_names.dart';
import 'symbols.dart';

/// Resolves source units and collects declarations, references, and live roots.
class DeadCodeSymbolCollector {
  final AnalyzerConfig config;

  const DeadCodeSymbolCollector(this.config);

  Future<DeadCodeSymbols> collect(
    String targetPath, {
    Iterable<String> excludedPaths = const [],
  }) async {
    final stopwatch = Stopwatch()..start();
    final discovery = SourceDiscovery(config);
    const libraryNames = DeadCodeLibraryNames();
    final absTarget = p.normalize(p.absolute(targetPath));
    final analysisRoot = await FileSystemEntity.isFile(absTarget)
        ? p.dirname(absTarget)
        : absTarget;
    final normalizedExcludedPaths = excludedPaths
        .map((path) => p.normalize(p.absolute(path)))
        .toList();
    final dartFiles =
        (await discovery.collect(
            absTarget,
          )).map((file) => p.normalize(p.absolute(file))).where((file) {
            return !discovery.shouldExclude(
              file,
              analysisRoot: analysisRoot,
              excludedPaths: normalizedExcludedPaths,
            );
          }).toList()
          ..sort();
    final collection = AnalysisContextCollection(
      includedPaths: [absTarget],
      excludedPaths: normalizedExcludedPaths,
    );
    dartFiles.removeWhere(
      (file) => !collection.contexts.any(
        (context) => context.contextRoot.isAnalyzed(file),
      ),
    );

    final allDeclarations = <CodeEntity>[];
    final allReferences = <String>{};
    final elementKeyToEntity = <String, CodeEntity>{};
    final referenceGraph = <String, Set<String>>{};
    final rootElementKeys = <String>{};
    final unresolvedMemberNames = <String>{};

    final parsedUnits = <String, CompilationUnit>{};
    final lineInfos = <String, LineInfo>{};
    final resolutionFailures = <String>[];
    for (final file in dartFiles) {
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        resolutionFailures.add(file);
        continue;
      }
      final errors = result.diagnostics.where(
        (diagnostic) =>
            diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR,
      );
      if (errors.isNotEmpty) {
        resolutionFailures.add('$file: ${errors.first.message}');
        continue;
      }
      parsedUnits[file] = result.unit;
      lineInfos[file] = result.lineInfo;
    }

    if (resolutionFailures.isNotEmpty) {
      throw StateError(
        'Could not resolve every Dart file under $targetPath:\n'
        '${resolutionFailures.join('\n')}',
      );
    }

    final packageRoots = await libraryNames.loadPackageRoots(absTarget);
    final exportedNames = libraryNames.collectExportedNames(
      parsedUnits,
      packageRoots,
    );
    final conditionallyLiveNames = libraryNames
        .collectConditionallyImportedNames(parsedUnits, packageRoots);

    for (final file in dartFiles) {
      final unit = parsedUnits[file];
      if (unit == null) {
        throw StateError('Missing resolved unit for $file');
      }

      final fileExports = exportedNames[file] ?? <String>{};
      final declarationVisitor = DeclarationVisitor(
        file,
        lineInfos[file]!,
        exportedNames: fileExports,
        liveNames: conditionallyLiveNames[file] ?? const {},
        ignoreMain: config.ignoreMain,
        entryPoints: config.entryPoints,
        entryPointAnnotations: config.entryPointAnnotations,
      );
      unit.accept(declarationVisitor);
      allDeclarations.addAll(declarationVisitor.declarations);
      elementKeyToEntity.addAll(declarationVisitor.elementKeyToEntity);
      rootElementKeys.addAll(declarationVisitor.liveElementKeys);

      final referenceVisitor = ReferenceVisitor();
      unit.accept(referenceVisitor);
      allReferences.addAll(referenceVisitor.allReferences);
      unresolvedMemberNames.addAll(referenceVisitor.unresolvedMemberNames);
      rootElementKeys.addAll(referenceVisitor.rootElementKeys);
      for (final entry in referenceVisitor.referenceGraph.entries) {
        referenceGraph.putIfAbsent(entry.key, () => {}).addAll(entry.value);
      }
    }

    stopwatch.stop();
    return DeadCodeSymbols(
      config: config,
      declarations: allDeclarations,
      references: allReferences,
      elementKeyToEntity: elementKeyToEntity,
      referenceGraph: referenceGraph,
      rootElementKeys: rootElementKeys,
      unresolvedMemberNames: unresolvedMemberNames,
      duration: stopwatch.elapsed,
    );
  }
}
