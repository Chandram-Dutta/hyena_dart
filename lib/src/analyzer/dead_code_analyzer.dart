import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../models/code_entity.dart';
import '../models/dead_code_report.dart';
import '../models/skipped_file.dart';
import 'ast_visitors/declaration_visitor.dart';
import 'ast_visitors/member_override.dart';
import 'ast_visitors/reference_visitor.dart';

/// Resolves a single Dart file. Used by [DeadCodeAnalyzer] and replaceable in
/// tests to simulate analyzer failures.
typedef ResolveDartUnit =
    Future<SomeResolvedUnitResult> Function(
      AnalysisSession session,
      String path,
    );

/// Finds declarations that are never referenced, using resolved analysis
/// from the official `analyzer` package.
class DeadCodeAnalyzer {
  /// Options and exceptions used by this analyzer.
  final AnalyzerConfig config;
  final ResolveDartUnit _resolveUnit;

  /// Creates a dead-code analyzer.
  ///
  /// Files that fail to resolve, contain analysis errors, or throw during
  /// analysis are skipped and listed in [DeadCodeReport.skippedFiles] instead
  /// of aborting the run. [resolveUnit] overrides how each file is resolved
  /// and exists mainly for tests.
  DeadCodeAnalyzer(this.config, {ResolveDartUnit? resolveUnit})
    : _resolveUnit = resolveUnit ?? _defaultResolveUnit;

  static Future<SomeResolvedUnitResult> _defaultResolveUnit(
    AnalysisSession session,
    String path,
  ) => session.getResolvedUnit(path);

  /// Analyzes the Dart package or directory at [targetPath].
  ///
  /// Files under any of [excludedPaths] (for example nested workspace
  /// packages) and files matching [AnalyzerConfig.excludePatterns] are
  /// skipped.
  Future<DeadCodeReport> analyze(
    String targetPath, {
    Iterable<String> excludedPaths = const [],
  }) async {
    final analysis = await _analyze(targetPath, excludedPaths: excludedPaths);
    return _buildReports([analysis]).single;
  }

  /// Analyzes several workspace packages together, sharing one reference
  /// graph. A declaration counts as used if it is reachable from a root in
  /// any of the packages.
  ///
  /// Returns one report, with its analysis duration, for each entry in
  /// [packages], in the same order.
  static Future<List<({DeadCodeReport report, Duration duration})>>
  analyzeWorkspace(
    List<
      ({
        String targetPath,
        AnalyzerConfig config,
        Iterable<String> excludedPaths,
      })
    >
    packages,
  ) async {
    final analyses = <_DeadCodeAnalysis>[];
    for (final package in packages) {
      analyses.add(
        await DeadCodeAnalyzer(
          package.config,
        )._analyze(package.targetPath, excludedPaths: package.excludedPaths),
      );
    }
    final reports = _buildReports(analyses);
    return [
      for (var index = 0; index < reports.length; index++)
        (report: reports[index], duration: analyses[index].duration),
    ];
  }

  Future<_DeadCodeAnalysis> _analyze(
    String targetPath, {
    required Iterable<String> excludedPaths,
  }) async {
    final stopwatch = Stopwatch()..start();
    final absTarget = p.normalize(p.absolute(targetPath));
    final analysisRoot = await FileSystemEntity.isFile(absTarget)
        ? p.dirname(absTarget)
        : absTarget;
    final normalizedExcludedPaths = excludedPaths
        .map((path) => p.normalize(p.absolute(path)))
        .toList();
    final dartFiles =
        (await _collectDartFiles(
            absTarget,
          )).map((file) => p.normalize(p.absolute(file))).where((file) {
            return !_shouldExclude(
              file,
              analysisRoot: analysisRoot,
              excludedPaths: normalizedExcludedPaths,
            );
          }).toList()
          ..sort();
    final collection = AnalysisContextCollection(includedPaths: [absTarget]);
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
    // Units that resolved but contain errors. Their declarations are not
    // reported, but their references still keep other code alive.
    final brokenUnits = <String, CompilationUnit>{};
    final skippedFiles = <SkippedFile>[];
    for (final file in dartFiles) {
      final isGenerated = _isGeneratedFile(file);
      final SomeResolvedUnitResult result;
      try {
        result = await _resolveUnit(
          collection.contextFor(file).currentSession,
          file,
        );
      } catch (error) {
        // Generated files only contribute references; a stale or broken
        // generated file is ignored rather than reported.
        if (isGenerated) continue;
        skippedFiles.add(
          SkippedFile(
            filePath: file,
            reason: singleLineReason('Analyzer failed: $error'),
          ),
        );
        continue;
      }
      if (result is! ResolvedUnitResult) {
        if (isGenerated) continue;
        skippedFiles.add(
          SkippedFile(
            filePath: file,
            reason:
                'The analyzer could not resolve this file '
                '(${_describeInvalidResult(result)}).',
          ),
        );
        continue;
      }
      final errors = result.diagnostics
          .where(
            (diagnostic) =>
                diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR,
          )
          .toList();
      if (errors.isNotEmpty && !isGenerated) {
        final first = errors.first;
        final line = result.lineInfo.getLocation(first.offset).lineNumber;
        skippedFiles.add(
          SkippedFile(
            filePath: file,
            reason: singleLineReason(
              '${errors.length} analysis error${errors.length == 1 ? '' : 's'}'
              '; first at line $line: ${first.message}',
            ),
          ),
        );
        brokenUnits[file] = result.unit;
        continue;
      }
      parsedUnits[file] = result.unit;
      lineInfos[file] = result.lineInfo;
    }

    final packageRoots = await _loadPackageRoots(absTarget);
    final exportedNames = _collectExportedNames(parsedUnits, packageRoots);
    final conditionallyLiveNames = _collectConditionallyImportedNames(
      parsedUnits,
      packageRoots,
    );

    for (final MapEntry(key: file, value: unit) in parsedUnits.entries) {
      if (_isGeneratedFile(file)) {
        try {
          _collectGeneratedReferences(
            unit,
            references: allReferences,
            unresolvedMemberNames: unresolvedMemberNames,
            rootElementKeys: rootElementKeys,
          );
        } catch (_) {
          // Best effort, like broken units: generated code never aborts a run.
        }
        continue;
      }

      final DeclarationVisitor declarationVisitor;
      final ReferenceVisitor referenceVisitor;
      try {
        declarationVisitor = DeclarationVisitor(
          file,
          lineInfos[file]!,
          exportedNames: exportedNames[file] ?? <String>{},
          liveNames: conditionallyLiveNames[file] ?? const {},
          ignoreMain: config.ignoreMain,
          entryPoints: config.entryPoints,
          entryPointAnnotations: config.entryPointAnnotations,
        );
        unit.accept(declarationVisitor);
        referenceVisitor = ReferenceVisitor();
        unit.accept(referenceVisitor);
      } catch (error) {
        skippedFiles.add(
          SkippedFile(
            filePath: file,
            reason: singleLineReason('Analysis failed: $error'),
          ),
        );
        continue;
      }
      allDeclarations.addAll(declarationVisitor.declarations);
      elementKeyToEntity.addAll(declarationVisitor.elementKeyToEntity);
      rootElementKeys.addAll(declarationVisitor.liveElementKeys);

      allReferences.addAll(referenceVisitor.allReferences);
      unresolvedMemberNames.addAll(referenceVisitor.unresolvedMemberNames);
      rootElementKeys.addAll(referenceVisitor.rootElementKeys);
      for (final entry in referenceVisitor.referenceGraph.entries) {
        referenceGraph.putIfAbsent(entry.key, () => {}).addAll(entry.value);
      }
    }

    for (final unit in brokenUnits.values) {
      // Best effort: anything a broken file references is treated as used, so
      // skipping it does not turn its dependencies into false positives.
      final referenceVisitor = ReferenceVisitor();
      try {
        unit.accept(referenceVisitor);
      } catch (_) {
        continue;
      }
      allReferences.addAll(referenceVisitor.allReferences);
      unresolvedMemberNames.addAll(referenceVisitor.unresolvedMemberNames);
      rootElementKeys
        ..addAll(referenceVisitor.rootElementKeys)
        ..addAll(referenceVisitor.referenceGraph.values.expand((keys) => keys));
    }

    skippedFiles.sort((a, b) => a.filePath.compareTo(b.filePath));
    stopwatch.stop();
    return _DeadCodeAnalysis(
      config: config,
      declarations: allDeclarations,
      references: allReferences,
      elementKeyToEntity: elementKeyToEntity,
      referenceGraph: referenceGraph,
      rootElementKeys: rootElementKeys,
      unresolvedMemberNames: unresolvedMemberNames,
      skippedFiles: skippedFiles,
      duration: stopwatch.elapsed,
    );
  }

  static String _describeInvalidResult(SomeResolvedUnitResult result) =>
      switch (result) {
        InvalidPathResult() => 'invalid path',
        NotPathOfUriResult() => 'path does not match its URI',
        UriOfExternalLibraryResult() => 'file belongs to an external library',
        DisposedAnalysisContextResult() => 'analysis context was disposed',
        MissingSdkLibraryResult(:final missingUri) =>
          'missing SDK library $missingUri',
        _ => 'unexpected result ${result.runtimeType}',
      };

  /// Whether [filePath] is code-generator output (json_serializable, freezed,
  /// mockito, ...). Such files are analyzed for references only; their own
  /// declarations are never reported.
  static bool _isGeneratedFile(String filePath) =>
      filePath.endsWith('.g.dart') ||
      filePath.endsWith('.freezed.dart') ||
      filePath.endsWith('.mocks.dart');

  /// Treats everything referenced from a generated [unit] as live.
  ///
  /// Generated declarations are not tracked, so they cannot act as graph
  /// sources; every element they reference becomes a root instead.
  void _collectGeneratedReferences(
    CompilationUnit unit, {
    required Set<String> references,
    required Set<String> unresolvedMemberNames,
    required Set<String> rootElementKeys,
  }) {
    final referenceVisitor = ReferenceVisitor();
    unit.accept(referenceVisitor);
    references.addAll(referenceVisitor.allReferences);
    unresolvedMemberNames.addAll(referenceVisitor.unresolvedMemberNames);
    rootElementKeys.addAll(referenceVisitor.rootElementKeys);
    for (final targets in referenceVisitor.referenceGraph.values) {
      rootElementKeys.addAll(targets);
    }
    // Generated overrides (mocks, freezed impls) keep the members they
    // implement alive.
    rootElementKeys.addAll(overriddenMemberKeys(unit));
  }

  Future<List<String>> _collectDartFiles(String targetPath) async {
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

  bool _shouldExclude(
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

    final segments = p.split(normalizedPath);
    if (segments.contains('.dart_tool') ||
        segments.contains('build') ||
        segments.contains('generated')) {
      return true;
    }

    return false;
  }

  Map<String, Set<String>> _collectExportedNames(
    Map<String, CompilationUnit> parsedUnits,
    Map<String, String> packageRoots,
  ) {
    final exportedNames = <String, Set<String>>{};
    final libraryFiles = _collectLibraryFiles(parsedUnits, packageRoots);

    for (final entry in parsedUnits.entries) {
      if (_isPublicLibrary(entry.key, entry.value, packageRoots.values)) {
        _addLibraryNames(exportedNames, entry.key, parsedUnits, libraryFiles);
      }
    }

    for (final entry in parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;

      for (final directive in unit.directives) {
        if (directive is ExportDirective) {
          for (final uri in _namespaceDirectiveUris(directive)) {
            final exportedFile = _resolveImportUri(file, uri, packageRoots);
            if (exportedFile != null) {
              _addLibraryNames(
                exportedNames,
                exportedFile,
                parsedUnits,
                libraryFiles,
                combinators: directive.combinators,
              );
            }
          }
        }
      }
    }

    return exportedNames;
  }

  Map<String, Set<String>> _collectConditionallyImportedNames(
    Map<String, CompilationUnit> parsedUnits,
    Map<String, String> packageRoots,
  ) {
    final liveNames = <String, Set<String>>{};
    final libraryFiles = _collectLibraryFiles(parsedUnits, packageRoots);
    for (final entry in parsedUnits.entries) {
      for (final directive
          in entry.value.directives.whereType<ImportDirective>()) {
        if (directive.configurations.isEmpty) continue;
        for (final uri in _namespaceDirectiveUris(directive)) {
          final importedFile = _resolveImportUri(entry.key, uri, packageRoots);
          if (importedFile == null) continue;
          _addLibraryNames(
            liveNames,
            importedFile,
            parsedUnits,
            libraryFiles,
            combinators: directive.combinators,
          );
        }
      }
    }
    return liveNames;
  }

  Iterable<String> _namespaceDirectiveUris(NamespaceDirective directive) sync* {
    final defaultUri = directive.uri.stringValue;
    if (defaultUri != null) yield defaultUri;
    for (final configuration in directive.configurations) {
      final uri = configuration.uri.stringValue;
      if (uri != null) yield uri;
    }
  }

  Map<String, Set<String>> _collectLibraryFiles(
    Map<String, CompilationUnit> parsedUnits,
    Map<String, String> packageRoots,
  ) {
    final libraryFiles = <String, Set<String>>{};
    for (final entry in parsedUnits.entries) {
      if (entry.value.directives.any((node) => node is PartOfDirective)) {
        continue;
      }

      final files = libraryFiles.putIfAbsent(entry.key, () => {entry.key});
      for (final directive
          in entry.value.directives.whereType<PartDirective>()) {
        final uri = directive.uri.stringValue;
        if (uri == null) continue;
        final partFile = _resolveImportUri(entry.key, uri, packageRoots);
        if (partFile != null && parsedUnits.containsKey(partFile)) {
          files.add(partFile);
        }
      }
    }
    return libraryFiles;
  }

  bool _isPublicLibrary(
    String file,
    CompilationUnit unit,
    Iterable<String> packageRoots,
  ) {
    if (unit.directives.any((node) => node is PartOfDirective)) return false;

    for (final root in packageRoots) {
      if (!p.isWithin(root, file)) continue;
      final segments = p.split(p.relative(file, from: root));
      return segments.isNotEmpty && segments.first != 'src';
    }
    return false;
  }

  void _addLibraryNames(
    Map<String, Set<String>> exportedNames,
    String definingFile,
    Map<String, CompilationUnit> parsedUnits,
    Map<String, Set<String>> libraryFiles, {
    Iterable<Combinator> combinators = const [],
  }) {
    final files = libraryFiles[definingFile] ?? {definingFile};
    final namesByFile = <String, Set<String>>{};
    final visibleNames = <String>{};
    for (final file in files) {
      final unit = parsedUnits[file];
      if (unit == null) continue;
      final names = _topLevelDeclarationNames(unit);
      namesByFile[file] = names;
      visibleNames.addAll(names);
    }

    for (final combinator in combinators) {
      if (combinator is ShowCombinator) {
        visibleNames.retainAll(combinator.shownNames.map((name) => name.name));
      } else if (combinator is HideCombinator) {
        visibleNames.removeAll(combinator.hiddenNames.map((name) => name.name));
      }
    }

    for (final entry in namesByFile.entries) {
      exportedNames
          .putIfAbsent(entry.key, () => {})
          .addAll(entry.value.intersection(visibleNames));
    }
  }

  Set<String> _topLevelDeclarationNames(CompilationUnit unit) {
    final names = <String>{};
    for (final declaration in unit.declarations) {
      if (declaration is TopLevelVariableDeclaration) {
        names.addAll(
          declaration.variables.variables.map(
            (variable) => variable.name.lexeme,
          ),
        );
      } else if (declaration is ExtensionDeclaration) {
        final name = declaration.name?.lexeme;
        if (name != null) names.add(name);
      } else {
        final name = switch (declaration) {
          ClassDeclaration() => declaration.namePart.typeName,
          EnumDeclaration() => declaration.namePart.typeName,
          ExtensionTypeDeclaration() => declaration.namePart.typeName,
          MixinDeclaration() => declaration.name,
          FunctionDeclaration() => declaration.name,
          TypeAlias() => declaration.name,
          _ => null,
        };
        if (name != null) names.add(name.lexeme);
      }
    }
    return names.where((name) => !name.startsWith('_')).toSet();
  }

  String? _resolveImportUri(
    String fromFile,
    String uri,
    Map<String, String> packageRoots,
  ) {
    if (uri.startsWith('dart:')) return null;

    if (uri.startsWith('package:')) {
      final withoutScheme = uri.substring('package:'.length);
      final slash = withoutScheme.indexOf('/');
      if (slash < 0) return null;
      final pkg = withoutScheme.substring(0, slash);
      final rest = withoutScheme.substring(slash + 1);
      final root = packageRoots[pkg];
      if (root == null) return null;
      return p.normalize(p.join(root, rest));
    }

    final fromDir = p.dirname(fromFile);
    return p.normalize(p.join(fromDir, uri));
  }

  Future<Map<String, String>> _loadPackageRoots(String targetPath) async {
    var dir = Directory(p.absolute(targetPath));
    while (true) {
      final configFile = File(
        p.join(dir.path, '.dart_tool', 'package_config.json'),
      );
      if (await configFile.exists()) {
        try {
          final json = jsonDecode(await configFile.readAsString());
          final packages = json['packages'] as List?;
          if (packages == null) return {};
          final roots = <String, String>{};
          for (final entry in packages) {
            final name = entry['name'] as String?;
            final rootUri = entry['rootUri'] as String?;
            final packageUri = entry['packageUri'] as String? ?? 'lib/';
            if (name == null || rootUri == null) continue;
            final resolvedRoot = rootUri.startsWith('file://')
                ? Uri.parse(rootUri).toFilePath()
                : p.normalize(p.join(configFile.parent.path, rootUri));
            roots[name] = p.normalize(p.join(resolvedRoot, packageUri));
          }
          return roots;
        } catch (_) {
          return {};
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return {};
      dir = parent;
    }
  }

  static List<DeadCodeReport> _buildReports(List<_DeadCodeAnalysis> analyses) {
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
        skippedFiles: analysis.skippedFiles,
      );
    }).toList();
  }

  static Set<String> _findReachableElements(
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

  static bool _isUsed(
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

class _DeadCodeAnalysis {
  final AnalyzerConfig config;
  final List<CodeEntity> declarations;
  final Set<String> references;
  final Map<String, CodeEntity> elementKeyToEntity;
  final Map<String, Set<String>> referenceGraph;
  final Set<String> rootElementKeys;
  final Set<String> unresolvedMemberNames;
  final List<SkippedFile> skippedFiles;
  final Duration duration;

  const _DeadCodeAnalysis({
    required this.config,
    required this.declarations,
    required this.references,
    required this.elementKeyToEntity,
    required this.referenceGraph,
    required this.rootElementKeys,
    required this.unresolvedMemberNames,
    required this.skippedFiles,
    required this.duration,
  });
}
