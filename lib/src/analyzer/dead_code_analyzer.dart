import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
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
    )).map(p.absolute).toList();
    final collection = AnalysisContextCollection(includedPaths: [absTarget]);

    final allDeclarations = <CodeEntity>[];
    final allReferences = <String>{};
    final elementIdToEntity = <int, CodeEntity>{};
    final referencedElementIds = <int>{};

    final parsedUnits = <String, CompilationUnit>{};
    final lineInfos = <String, LineInfo>{};
    var resolvedCount = 0;
    for (final file in dartFiles) {
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) continue;
      parsedUnits[file] = result.unit;
      lineInfos[file] = result.lineInfo;
      resolvedCount++;
    }

    if (resolvedCount == 0 && dartFiles.isNotEmpty) {
      throw StateError(
        'Could not resolve any Dart files under $targetPath. '
        'Ensure the path is inside a Dart package and `dart pub get` has been run.',
      );
    }

    final packageRoots = await _loadPackageRoots(absTarget);
    final exportedNames = _collectExportedNames(parsedUnits, packageRoots);

    for (final file in dartFiles) {
      if (_shouldExclude(file)) continue;
      final unit = parsedUnits[file];
      if (unit == null) continue;

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
      referencedElementIds.addAll(referenceVisitor.referencedElementIds);
    }

    final unusedEntities = _findUnusedEntities(
      allDeclarations,
      allReferences,
      elementIdToEntity,
      referencedElementIds,
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
    final fileExports = <String, List<String>>{};

    for (final entry in parsedUnits.entries) {
      final file = entry.key;
      final unit = entry.value;

      for (final directive in unit.directives) {
        if (directive is ExportDirective) {
          final uri = directive.uri.stringValue;
          if (uri != null) {
            final exportedFile = _resolveImportUri(file, uri, packageRoots);
            if (exportedFile != null) {
              fileExports.putIfAbsent(file, () => []).add(exportedFile);

              final showNames = <String>{};
              for (final combinator in directive.combinators) {
                if (combinator is ShowCombinator) {
                  for (final name in combinator.shownNames) {
                    showNames.add(name.name);
                  }
                }
              }
              if (showNames.isNotEmpty) {
                exportedNames
                    .putIfAbsent(exportedFile, () => {})
                    .addAll(showNames);
              }
            }
          }
        }
      }
    }

    for (final entry in fileExports.entries) {
      for (final exportedFile in entry.value) {
        if (!exportedNames.containsKey(exportedFile)) {
          exportedNames[exportedFile] = {'*'};
        }
      }
    }

    return exportedNames;
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
    Set<int> referencedElementIds,
  ) {
    final entityToId = <CodeEntity, int>{};
    for (final entry in elementIdToEntity.entries) {
      entityToId[entry.value] = entry.key;
    }

    final unused = <CodeEntity>[];
    for (final entity in declarations) {
      if (_isUsed(entity, references, entityToId, referencedElementIds)) {
        continue;
      }
      if (config.ignoreExports && entity.isExported) continue;
      if (!entity.isPublic && config.ignorePrivate) continue;
      unused.add(entity);
    }
    return unused;
  }

  bool _isUsed(
    CodeEntity entity,
    Set<String> references,
    Map<CodeEntity, int> entityToId,
    Set<int> referencedElementIds,
  ) {
    final id = entityToId[entity];
    if (id != null) {
      return referencedElementIds.contains(id);
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
