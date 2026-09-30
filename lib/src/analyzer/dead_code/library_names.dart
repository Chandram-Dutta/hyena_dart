import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// Resolves library visibility, parts, and conditional namespaces.
class DeadCodeLibraryNames {
  const DeadCodeLibraryNames();

  Map<String, Set<String>> collectExportedNames(
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

  Map<String, Set<String>> collectConditionallyImportedNames(
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

  Future<Map<String, String>> loadPackageRoots(String targetPath) async {
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
}
