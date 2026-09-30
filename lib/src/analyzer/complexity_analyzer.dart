import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/error/error.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../models/complexity_metrics.dart';
import 'ast_visitors/complexity_visitor.dart';
import 'source_discovery.dart';

class ComplexityAnalyzer {
  final AnalyzerConfig config;

  ComplexityAnalyzer(this.config);

  Future<ComplexityReport> analyze(
    String targetPath, {
    Iterable<String> excludedPaths = const [],
  }) async {
    final discovery = SourceDiscovery(config);
    final absoluteTarget = p.normalize(p.absolute(targetPath));
    final analysisRoot = await FileSystemEntity.isFile(absoluteTarget)
        ? p.dirname(absoluteTarget)
        : absoluteTarget;
    final normalizedExcludedPaths = excludedPaths
        .map((path) => p.normalize(p.absolute(path)))
        .toList();
    final dartFiles = (await discovery.collect(
      absoluteTarget,
    )).map((file) => p.normalize(p.absolute(file))).toList()..sort();
    final collection = AnalysisContextCollection(
      includedPaths: [absoluteTarget],
      excludedPaths: normalizedExcludedPaths,
    );
    dartFiles.removeWhere(
      (file) => !collection.contexts.any(
        (context) => context.contextRoot.isAnalyzed(file),
      ),
    );
    final fileMetrics = <FileMetrics>[];

    for (final file in dartFiles) {
      if (discovery.shouldExclude(
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
