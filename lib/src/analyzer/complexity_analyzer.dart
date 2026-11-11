import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/error/error.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../models/complexity_metrics.dart';
import '../models/skipped_file.dart';
import 'ast_visitors/complexity_visitor.dart';

/// Reads the source text of a Dart file. Used by [ComplexityAnalyzer] and
/// replaceable in tests to simulate unreadable files.
typedef ReadDartSource = Future<String> Function(String path);

class ComplexityAnalyzer {
  final AnalyzerConfig config;
  final ReadDartSource _readSource;

  /// Creates a complexity analyzer.
  ///
  /// Files that cannot be read, contain syntax errors, or throw during
  /// analysis are skipped and listed in [ComplexityReport.skippedFiles]
  /// instead of aborting the run. [readSource] overrides how each file is read
  /// and exists mainly for tests.
  ComplexityAnalyzer(this.config, {ReadDartSource? readSource})
    : _readSource = readSource ?? _defaultReadSource;

  static Future<String> _defaultReadSource(String path) =>
      File(path).readAsString();

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
    final dartFiles = (await _collectDartFiles(
      absoluteTarget,
    )).map((file) => p.normalize(p.absolute(file))).toList()..sort();
    final collection = AnalysisContextCollection(
      includedPaths: [absoluteTarget],
    );
    dartFiles.removeWhere(
      (file) => !collection.contexts.any(
        (context) => context.contextRoot.isAnalyzed(file),
      ),
    );
    final fileMetrics = <FileMetrics>[];
    final skippedFiles = <SkippedFile>[];

    for (final file in dartFiles) {
      if (_shouldExclude(
        file,
        analysisRoot: analysisRoot,
        excludedPaths: normalizedExcludedPaths,
      )) {
        continue;
      }

      try {
        fileMetrics.add(await _analyzeFile(file));
      } on _SkipFile catch (skip) {
        skippedFiles.add(SkippedFile(filePath: file, reason: skip.reason));
      } catch (error) {
        skippedFiles.add(
          SkippedFile(
            filePath: file,
            reason: singleLineReason('Analysis failed: $error'),
          ),
        );
      }
    }

    return ComplexityReport(
      files: fileMetrics,
      cyclomaticThreshold: config.cyclomaticThreshold,
      maxNestingLevel: config.maxNestingLevel,
      maxParameters: config.maxParameters,
      skippedFiles: skippedFiles,
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

    for (final pattern in config.excludePatterns) {
      final glob = Glob(pattern);
      if (glob.matches(relativePath) || glob.matches(absolutePath)) {
        return true;
      }
    }

    if (normalizedPath.endsWith('.g.dart') ||
        normalizedPath.endsWith('.freezed.dart') ||
        normalizedPath.endsWith('.mocks.dart')) {
      return true;
    }

    final segments = p.split(normalizedPath);
    if (segments.contains('.dart_tool') ||
        segments.contains('build') ||
        segments.contains('generated')) {
      return true;
    }

    return false;
  }

  Future<FileMetrics> _analyzeFile(String filePath) async {
    final String content;
    try {
      content = await _readSource(filePath);
    } on FileSystemException catch (error) {
      final osMessage = error.osError?.message;
      throw _SkipFile(
        singleLineReason(
          'Could not read file: ${error.message}'
          '${osMessage == null || osMessage.isEmpty ? '' : ' ($osMessage)'}',
        ),
      );
    }
    final ParseStringResult result;
    try {
      result = parseString(
        content: content,
        path: filePath,
        throwIfDiagnostics: false,
      );
    } on ArgumentError catch (error) {
      throw _SkipFile(singleLineReason('Could not parse: ${error.message}'));
    }
    final errors = result.errors
        .where(
          (diagnostic) =>
              diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR,
        )
        .toList();
    if (errors.isNotEmpty) {
      final first = errors.first;
      final line = result.lineInfo.getLocation(first.offset).lineNumber;
      throw _SkipFile(
        singleLineReason(
          '${errors.length} syntax error${errors.length == 1 ? '' : 's'}'
          '; first at line $line: ${first.message}',
        ),
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

/// Signals that a file cannot be analyzed and should be reported as skipped.
class _SkipFile implements Exception {
  final String reason;

  const _SkipFile(this.reason);
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
