import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/error/error.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../models/complexity_metrics.dart';
import 'ast_visitors/complexity_visitor.dart';
import 'source_file_filter.dart';

class ComplexityAnalyzer {
  final AnalyzerConfig config;

  ComplexityAnalyzer(this.config);

  Future<ComplexityReport> analyze(
    String targetPath, {
    Iterable<String> excludedPaths = const [],
  }) async {
    final absoluteTarget = p.normalize(p.absolute(targetPath));
    final analysisRoot = await FileSystemEntity.isFile(absoluteTarget)
        ? p.dirname(absoluteTarget)
        : absoluteTarget;
    final normalizedExcludedPaths = excludedPaths
        .map((path) => p.normalize(p.absolute(path)))
        .toList();
    final dartFiles = await _collectDartFiles(absoluteTarget)
      ..sort();
    final fileMetrics = <FileMetrics>[];

    for (final file in dartFiles) {
      if (_shouldExclude(
        file,
        analysisRoot: analysisRoot,
        excludedPaths: normalizedExcludedPaths,
      )) {
        continue;
      }

      final metrics = await _analyzeFile(file);
      fileMetrics.add(metrics);
    }

    return ComplexityReport(
      files: fileMetrics,
      cyclomaticThreshold: config.cyclomaticThreshold,
      maxNestingLevel: config.maxNestingLevel,
      maxParameters: config.maxParameters,
    );
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

    if (isDefaultExcludedSourcePath(
      p.relative(normalizedPath, from: analysisRoot),
    )) {
      return true;
    }

    for (final pattern in config.excludePatterns) {
      final glob = Glob(pattern);
      if (glob.matches(relativePath) || glob.matches(absolutePath)) {
        return true;
      }
    }

    return false;
  }

  Future<FileMetrics> _analyzeFile(String filePath) async {
    final content = await File(filePath).readAsString();
    late final ParseStringResult result;
    try {
      result = parseString(
        content: content,
        path: filePath,
        throwIfDiagnostics: false,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Could not parse $filePath: ${error.message}');
    }
    final errors = result.errors.where(
      (diagnostic) =>
          diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR,
    );
    if (errors.isNotEmpty) {
      throw FormatException(
        'Could not parse $filePath: ${errors.first.message}',
      );
    }

    final complexityVisitor = ComplexityVisitor(
      filePath,
      result.lineInfo,
      content,
    );
    result.unit.accept(complexityVisitor);

    final lines = const LineSplitter().convert(content);
    final lineStats = _countLines(lines);

    return FileMetrics(
      filePath: filePath,
      totalLines: lines.length,
      codeLines: lineStats.codeLines,
      commentLines: lineStats.commentLines,
      blankLines: lineStats.blankLines,
      functions: complexityVisitor.functions,
    );
  }

  _LineStats _countLines(List<String> lines) {
    int codeLines = 0;
    int commentLines = 0;
    int blankLines = 0;
    bool inBlockComment = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        blankLines++;
        continue;
      }

      if (inBlockComment) {
        commentLines++;
        if (trimmed.contains('*/')) {
          inBlockComment = false;
        }
        continue;
      }

      if (trimmed.startsWith('/*')) {
        commentLines++;
        if (!trimmed.contains('*/')) {
          inBlockComment = true;
        }
        continue;
      }

      if (trimmed.startsWith('//')) {
        commentLines++;
        continue;
      }

      codeLines++;
    }

    return _LineStats(
      codeLines: codeLines,
      commentLines: commentLines,
      blankLines: blankLines,
    );
  }
}

class _LineStats {
  final int codeLines;
  final int commentLines;
  final int blankLines;

  _LineStats({
    required this.codeLines,
    required this.commentLines,
    required this.blankLines,
  });
}
