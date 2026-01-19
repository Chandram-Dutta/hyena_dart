import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
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
    final dartFiles = await _collectDartFiles(targetPath);
    final allDeclarations = <CodeEntity>[];
    final allReferences = <String>{};
    final exportedNames = await _collectExportedNames(dartFiles);

    for (final file in dartFiles) {
      if (_shouldExclude(file)) continue;

      final content = await File(file).readAsString();
      final result = parseString(
        content: content,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      final unit = result.unit;

      final fileExports = exportedNames[file] ?? <String>{};
      final declarationVisitor = DeclarationVisitor(
        file,
        exportedNames: fileExports,
      );
      unit.accept(declarationVisitor);
      allDeclarations.addAll(declarationVisitor.declarations);

      final referenceVisitor = ReferenceVisitor();
      unit.accept(referenceVisitor);
      allReferences.addAll(referenceVisitor.allReferences);
    }

    final unusedEntities = _findUnusedEntities(allDeclarations, allReferences);

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
        filePath.endsWith('.mocks.dart') ||
        filePath.contains('/generated/')) {
      return true;
    }

    return false;
  }

  Future<Map<String, Set<String>>> _collectExportedNames(
    List<String> files,
  ) async {
    final exportedNames = <String, Set<String>>{};
    final fileExports = <String, List<String>>{};

    for (final file in files) {
      final content = await File(file).readAsString();
      final result = parseString(
        content: content,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      final unit = result.unit;

      for (final directive in unit.directives) {
        if (directive is ExportDirective) {
          final uri = directive.uri.stringValue;
          if (uri != null) {
            final exportedFile = _resolveImportUri(file, uri);
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

  String? _resolveImportUri(String fromFile, String uri) {
    if (uri.startsWith('dart:') || uri.startsWith('package:')) {
      return null;
    }

    final fromDir = p.dirname(fromFile);
    return p.normalize(p.join(fromDir, uri));
  }

  List<CodeEntity> _findUnusedEntities(
    List<CodeEntity> declarations,
    Set<String> references,
  ) {
    final unused = <CodeEntity>[];

    for (final entity in declarations) {
      if (_isUsed(entity, references)) continue;

      if (config.ignoreExports && entity.isExported) continue;

      if (!entity.isPublic && config.ignorePrivate) continue;

      unused.add(entity);
    }

    return unused;
  }

  bool _isUsed(CodeEntity entity, Set<String> references) {
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
