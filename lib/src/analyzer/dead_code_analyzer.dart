import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../models/code_entity.dart';
import '../models/dead_code_report.dart';
import 'ast_visitors/declaration_visitor.dart';
import 'ast_visitors/reference_visitor.dart';

class DeadCodeAnalyzer {
  final AnalyzerConfig config;

  DeadCodeAnalyzer(this.config);

  Future<DeadCodeReport> analyze(String targetPath) async {
    final absTarget = p.absolute(targetPath);
    final dartFiles = (await _collectDartFiles(
      absTarget,
    )).map(p.absolute).where((file) => !_shouldExclude(file)).toList();
    final collection = AnalysisContextCollection(includedPaths: [absTarget]);

    final allDeclarations = <CodeEntity>[];
    final allReferences = <String>{};
    final elementIdToEntity = <int, CodeEntity>{};
    final referenceGraph = <int, Set<int>>{};
    final rootElementIds = <int>{};

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
      final errors = result.errors.where(
        (error) => error.errorCode.errorSeverity == ErrorSeverity.ERROR,
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

    final packageRoots = await _loadPackageRoots(absTarget);
    final exportedNames = _collectExportedNames(parsedUnits, packageRoots);

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
        ignoreMain: config.ignoreMain,
      );
      unit.accept(declarationVisitor);
      allDeclarations.addAll(declarationVisitor.declarations);
      elementIdToEntity.addAll(declarationVisitor.elementIdToEntity);

      final referenceVisitor = ReferenceVisitor();
      unit.accept(referenceVisitor);
      allReferences.addAll(referenceVisitor.allReferences);
      rootElementIds.addAll(referenceVisitor.rootElementIds);
      for (final entry in referenceVisitor.referenceGraph.entries) {
        referenceGraph.putIfAbsent(entry.key, () => {}).addAll(entry.value);
      }
    }

    final unusedEntities = _findUnusedEntities(
      allDeclarations,
      allReferences,
      elementIdToEntity,
      referenceGraph,
      rootElementIds,
    );

    return DeadCodeReport(
      unusedEntities: unusedEntities,
      totalDeclarations: allDeclarations.length,
    );
  }

  Future<List<String>> _collectDartFiles(String targetPath) async {
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

  bool _shouldExclude(String filePath) {
    final relativePath = p.relative(filePath);

    for (final pattern in config.excludePatterns) {
      final glob = Glob(pattern);
      if (glob.matches(relativePath) || glob.matches(filePath)) {
        return true;
      }
    }

    if (filePath.endsWith('.g.dart') ||
        filePath.endsWith('.freezed.dart') ||
        filePath.endsWith('.mocks.dart')) {
      return true;
    }

    final segments = p.split(filePath);
    if (segments.contains('generated')) {
      return true;
    }

    return false;
  }

  Map<String, Set<String>> _collectExportedNames(
    Map<String, CompilationUnit> parsedUnits,
    Map<String, String> packageRoots,
  ) {
    final exportedNames = <String, Set<String>>{};

    for (final entry in parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;

      for (final directive in unit.directives) {
        if (directive is ExportDirective) {
          final uri = directive.uri.stringValue;
          if (uri != null) {
            final exportedFile = _resolveImportUri(file, uri, packageRoots);
            if (exportedFile != null) {
              final exportedUnit = parsedUnits[exportedFile];
              if (exportedUnit == null) continue;
              final visibleNames = _topLevelDeclarationNames(exportedUnit);
              for (final combinator in directive.combinators) {
                if (combinator is ShowCombinator) {
                  final shownNames = combinator.shownNames
                      .map((name) => name.name)
                      .toSet();
                  visibleNames.retainAll(shownNames);
                } else if (combinator is HideCombinator) {
                  visibleNames.removeAll(
                    combinator.hiddenNames.map((name) => name.name),
                  );
                }
              }
              exportedNames
                  .putIfAbsent(exportedFile, () => {})
                  .addAll(visibleNames);
            }
          }
        }
      }
    }

    return exportedNames;
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
      } else if (declaration is NamedCompilationUnitMember) {
        names.add(declaration.name.lexeme);
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

  List<CodeEntity> _findUnusedEntities(
    List<CodeEntity> declarations,
    Set<String> references,
    Map<int, CodeEntity> elementIdToEntity,
    Map<int, Set<int>> referenceGraph,
    Set<int> rootElementIds,
  ) {
    final entityToId = <CodeEntity, int>{};
    for (final entry in elementIdToEntity.entries) {
      entityToId[entry.value] = entry.key;
    }

    for (final entry in elementIdToEntity.entries) {
      final entity = entry.value;
      if ((config.ignoreExports && entity.isExported) ||
          (config.ignorePrivate && !entity.isPublic)) {
        rootElementIds.add(entry.key);
      }
    }
    final reachableElementIds = _findReachableElements(
      referenceGraph,
      rootElementIds,
    );

    final unused = <CodeEntity>[];
    for (final entity in declarations) {
      if (_isUsed(entity, references, entityToId, reachableElementIds)) {
        continue;
      }
      if (config.ignoreExports && entity.isExported) continue;
      if (!entity.isPublic && config.ignorePrivate) continue;
      unused.add(entity);
    }
    return unused;
  }

  Set<int> _findReachableElements(
    Map<int, Set<int>> referenceGraph,
    Set<int> roots,
  ) {
    final reachable = <int>{...roots};
    final pending = roots.toList();
    while (pending.isNotEmpty) {
      final source = pending.removeLast();
      for (final target in referenceGraph[source] ?? const <int>{}) {
        if (reachable.add(target)) pending.add(target);
      }
    }
    return reachable;
  }

  bool _isUsed(
    CodeEntity entity,
    Set<String> references,
    Map<CodeEntity, int> entityToId,
    Set<int> reachableElementIds,
  ) {
    final id = entityToId[entity];
    if (id != null) {
      return reachableElementIds.contains(id);
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
