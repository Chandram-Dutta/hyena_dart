import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../config/analyzer_config.dart';
import '../models/complexity_metrics.dart';
import 'ast_visitors/complexity_visitor.dart';

class ComplexityAnalyzer {
  final AnalyzerConfig config;

  ComplexityAnalyzer(this.config);

  Future<ComplexityReport> analyze(String targetPath) async {
    final dartFiles = await _collectDartFiles(targetPath);
    final fileMetrics = <FileMetrics>[];

    for (final file in dartFiles) {
      if (_shouldExclude(file)) continue;

      final metrics = await _analyzeFile(file);
      if (metrics != null) {
        fileMetrics.add(metrics);
      }
    }

    return ComplexityReport(files: fileMetrics);
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

  Future<FileMetrics?> _analyzeFile(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final result = parseString(content: content);
      final unit = result.unit;

      final complexityVisitor = ComplexityVisitor(filePath);
      unit.accept(complexityVisitor);

      final lines = content.split('\n');
      final lineStats = _countLines(lines);

      return FileMetrics(
        filePath: filePath,
        totalLines: lines.length,
        codeLines: lineStats.codeLines,
        commentLines: lineStats.commentLines,
        blankLines: lineStats.blankLines,
        functions: complexityVisitor.functions,
      );
    } catch (e) {
      return null;
    }
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
