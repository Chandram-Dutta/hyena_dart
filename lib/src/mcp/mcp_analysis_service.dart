import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../analyzer/complexity_analyzer.dart';
import '../analyzer/dead_code_analyzer.dart';
import '../config/analyzer_config.dart';
import '../models/analysis_finding.dart';
import '../models/analysis_result.dart';

const _maxPathLength = 4096;
const _maxOutputTextLength = 4096;

class McpAnalysisLimits {
  final int maxDartFiles;
  final int maxSourceBytes;
  final int maxFindings;
  final Duration timeout;

  const McpAnalysisLimits({
    this.maxDartFiles = 10000,
    this.maxSourceBytes = 50 * 1024 * 1024,
    this.maxFindings = 200,
    this.timeout = const Duration(minutes: 2),
  });
}

class McpAnalysisException implements Exception {
  final String message;

  const McpAnalysisException(this.message);

  @override
  String toString() => message;
}

class McpAnalysisService {
  final String rootPath;
  final McpAnalysisLimits limits;

  bool _analysisInProgress = false;
  Completer<void>? _cancellation;

  McpAnalysisService._(this.rootPath, this.limits);

  static Future<McpAnalysisService> create(
    String rootPath, {
    McpAnalysisLimits limits = const McpAnalysisLimits(),
  }) async {
    final root = Directory(p.absolute(rootPath));
    if (!await root.exists()) {
      throw ArgumentError('MCP workspace root does not exist: $rootPath');
    }

    final resolvedRoot = p.normalize(await root.resolveSymbolicLinks());
    return McpAnalysisService._(resolvedRoot, limits);
  }

  Future<Map<String, Object?>> analyze({
    String targetPath = '.',
    String checks = 'both',
  }) async {
    if (!const {'both', 'dead-code', 'complexity'}.contains(checks)) {
      throw const McpAnalysisException(
        'Checks must be both, dead-code, or complexity.',
      );
    }
    if (_analysisInProgress) {
      throw const McpAnalysisException(
        'Another Hyena analysis is already in progress.',
      );
    }

    _analysisInProgress = true;
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    try {
      final target = await _resolveTarget(targetPath);
      return await _runWorker(target, checks, cancellation);
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
      _analysisInProgress = false;
    }
  }

  void cancelCurrentAnalysis() {
    final cancellation = _cancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  Future<String> _resolveTarget(String requestedPath) async {
    if (requestedPath.isEmpty || requestedPath.contains('\u0000')) {
      throw const McpAnalysisException(
        'Target path must not be empty or contain NUL characters.',
      );
    }
    if (requestedPath.length > _maxPathLength) {
      throw const McpAnalysisException(
        'Target path exceeds the 4096 character safety limit.',
      );
    }
    if (p.isAbsolute(requestedPath)) {
      throw const McpAnalysisException(
        'Target path must be relative to the configured workspace root.',
      );
    }

    final candidate = p.normalize(p.join(rootPath, requestedPath));
    if (!_isWithinOrEqual(rootPath, candidate)) {
      throw const McpAnalysisException(
        'Target path is outside the configured workspace root.',
      );
    }

    final type = await FileSystemEntity.type(candidate, followLinks: true);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw const McpAnalysisException('Target path does not exist.');
    }

    final resolved = p.normalize(
      type == FileSystemEntityType.file
          ? await File(candidate).resolveSymbolicLinks()
          : await Directory(candidate).resolveSymbolicLinks(),
    );
    if (!_isWithinOrEqual(rootPath, resolved)) {
      throw const McpAnalysisException(
        'Target path resolves outside the configured workspace root.',
      );
    }
    if (type == FileSystemEntityType.file && !resolved.endsWith('.dart')) {
      throw const McpAnalysisException(
        'Target file must be a Dart source file.',
      );
    }
    return resolved;
  }

  Future<Map<String, Object?>> _runWorker(
    String targetPath,
    String checks,
    Completer<void> cancellation,
  ) async {
    final responsePort = ReceivePort();
    Isolate? isolate;
    try {
      if (cancellation.isCompleted) {
        throw const McpAnalysisException('Hyena analysis was cancelled.');
      }
      isolate = await Isolate.spawn<List<Object?>>(_analysisWorker, [
        responsePort.sendPort,
        rootPath,
        targetPath,
        checks,
        limits.maxFindings,
        limits.maxDartFiles,
        limits.maxSourceBytes,
      ]);

      final response = await Future.any<Object?>([
        responsePort.first,
        cancellation.future.then((_) => _cancelled),
      ]).timeout(limits.timeout);
      if (identical(response, _cancelled)) {
        throw const McpAnalysisException('Hyena analysis was cancelled.');
      }
      if (response is! Map) {
        throw const McpAnalysisException(
          'Hyena analysis stopped before producing a result.',
        );
      }

      final message = response.cast<String, Object?>();
      if (message['result'] case final Map result) {
        return result.cast<String, Object?>();
      }
      throw McpAnalysisException(
        message['error'] as String? ?? 'Hyena analysis failed.',
      );
    } on TimeoutException {
      throw McpAnalysisException(
        'Hyena analysis exceeded the ${limits.timeout.inSeconds} second '
        'safety limit.',
      );
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      responsePort.close();
    }
  }
}

final _cancelled = Object();

bool _isWithinOrEqual(String rootPath, String candidatePath) =>
    p.equals(rootPath, candidatePath) || p.isWithin(rootPath, candidatePath);

void _analysisWorker(List<Object?> message) async {
  final sendPort = message[0] as SendPort;
  final rootPath = message[1] as String;
  final targetPath = message[2] as String;
  final checks = message[3] as String;
  final maxFindings = message[4] as int;
  final maxDartFiles = message[5] as int;
  final maxSourceBytes = message[6] as int;

  try {
    await _validateTargetContents(
      targetPath,
      maxDartFiles: maxDartFiles,
      maxSourceBytes: maxSourceBytes,
    );
    final result = await _performAnalysis(
      rootPath: rootPath,
      targetPath: targetPath,
      checks: checks,
      maxFindings: maxFindings,
    );
    sendPort.send(<String, Object?>{'result': result});
  } on McpAnalysisException catch (error) {
    sendPort.send(<String, Object?>{'error': error.message});
  } catch (_) {
    stderr.writeln('Hyena MCP analysis failed unexpectedly.');
    sendPort.send(<String, Object?>{
      'error':
          'Hyena could not analyze the target. Ensure it is a valid Dart '
          'package and run dart pub get before trying again.',
    });
  }
}

Future<void> _validateTargetContents(
  String targetPath, {
  required int maxDartFiles,
  required int maxSourceBytes,
}) async {
  final type = await FileSystemEntity.type(targetPath, followLinks: false);
  if (type == FileSystemEntityType.file) {
    final size = await File(targetPath).length();
    _checkLimits(
      fileCount: 1,
      sourceBytes: size,
      maxDartFiles: maxDartFiles,
      maxSourceBytes: maxSourceBytes,
    );
    return;
  }

  var fileCount = 0;
  var sourceBytes = 0;
  await for (final entity in Directory(
    targetPath,
  ).list(recursive: true, followLinks: false)) {
    if (entity is Link) {
      final linkType = await FileSystemEntity.type(
        entity.path,
        followLinks: true,
      );
      if (linkType == FileSystemEntityType.directory ||
          entity.path.endsWith('.dart')) {
        throw const McpAnalysisException(
          'Dart files and directories reached through symbolic links are '
          'not analyzed by the MCP server.',
        );
      }
      continue;
    }
    if (entity is! File || !entity.path.endsWith('.dart')) continue;

    fileCount++;
    sourceBytes += await entity.length();
    _checkLimits(
      fileCount: fileCount,
      sourceBytes: sourceBytes,
      maxDartFiles: maxDartFiles,
      maxSourceBytes: maxSourceBytes,
    );
  }
}

void _checkLimits({
  required int fileCount,
  required int sourceBytes,
  required int maxDartFiles,
  required int maxSourceBytes,
}) {
  if (fileCount > maxDartFiles) {
    throw McpAnalysisException(
      'Target exceeds the $maxDartFiles Dart file safety limit.',
    );
  }
  if (sourceBytes > maxSourceBytes) {
    final maxMiB = maxSourceBytes ~/ (1024 * 1024);
    throw McpAnalysisException(
      'Target exceeds the $maxMiB MiB Dart source safety limit.',
    );
  }
}

Future<Map<String, Object?>> _performAnalysis({
  required String rootPath,
  required String targetPath,
  required String checks,
  required int maxFindings,
}) async {
  final config = await AnalyzerConfig.load(
    null,
    targetPath: targetPath,
    searchBoundary: rootPath,
  );
  final stopwatch = Stopwatch()..start();

  final includeDeadCode = checks == 'both' || checks == 'dead-code';
  final includeComplexity = checks == 'both' || checks == 'complexity';
  final deadCodeReport = includeDeadCode
      ? await DeadCodeAnalyzer(config).analyze(targetPath)
      : null;
  final complexityReport = includeComplexity
      ? await ComplexityAnalyzer(config).analyze(targetPath)
      : null;
  stopwatch.stop();

  final analysisResult = AnalysisResult(
    deadCodeReport: deadCodeReport,
    complexityReport: complexityReport,
    targetPath: targetPath,
    duration: stopwatch.elapsed,
  );
  final findings =
      AnalysisFinding.fromResult(analysisResult, rootPath: rootPath)
        ..sort((left, right) {
          final pathComparison = left.filePath.compareTo(right.filePath);
          if (pathComparison != 0) return pathComparison;
          final lineComparison = left.line.compareTo(right.line);
          if (lineComparison != 0) return lineComparison;
          return left.ruleId.compareTo(right.ruleId);
        });
  final returnedFindings = findings.take(maxFindings).toList();

  final summary = <String, Object?>{
    'totalFindings': findings.length,
    'returnedFindings': returnedFindings.length,
    'truncated': findings.length > returnedFindings.length,
    if (deadCodeReport != null)
      'deadCode': <String, Object?>{
        'totalDeclarations': deadCodeReport.totalDeclarations,
        'unusedDeclarations': deadCodeReport.unusedCount,
      },
    if (complexityReport != null)
      'complexity': <String, Object?>{
        'files': complexityReport.totalFiles,
        'functions': complexityReport.totalFunctions,
        'lines': complexityReport.totalLines,
        'cyclomaticFindings': complexityReport.highComplexityFunctions.length,
        'nestingFindings': complexityReport.highNestingFunctions.length,
        'parameterFindings': complexityReport.highParameterFunctions.length,
      },
  };

  return <String, Object?>{
    'schemaVersion': 1,
    'target': _boundedText(_relativePath(targetPath, rootPath)),
    'checks': checks,
    'durationMs': stopwatch.elapsedMilliseconds,
    'summary': summary,
    'findings': returnedFindings
        .map((finding) => _findingToJson(finding, rootPath))
        .toList(),
  };
}

Map<String, Object?> _findingToJson(AnalysisFinding finding, String rootPath) =>
    <String, Object?>{
      'category': _boundedText(finding.category),
      'ruleId': _boundedText(finding.ruleId),
      'message': _boundedText(finding.message),
      'path': _boundedText(_relativePath(finding.filePath, rootPath)),
      'line': finding.line,
      if (finding.column != null) 'column': finding.column,
      'symbol': _boundedText(finding.symbol),
      'symbolType': _boundedText(finding.symbolType),
      if (finding.properties['value'] case final int value) 'value': value,
      if (finding.properties['threshold'] case final int threshold)
        'threshold': threshold,
    };

String _relativePath(String filePath, String rootPath) {
  final relative = p.relative(filePath, from: rootPath);
  return p.posix.joinAll(p.split(relative));
}

String _boundedText(String value) {
  if (value.length <= _maxOutputTextLength) return value;

  var end = _maxOutputTextLength - 1;
  final lastCodeUnit = value.codeUnitAt(end - 1);
  if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF) end--;
  return '${value.substring(0, end)}…';
}
