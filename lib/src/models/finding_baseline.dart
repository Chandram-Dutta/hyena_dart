import 'dart:convert';
import 'dart:io';

import 'analysis_finding.dart';
import 'analysis_path.dart';
import 'analysis_result.dart';
import 'complexity_metrics.dart';
import 'dead_code_report.dart';

class FindingBaseline {
  static const currentVersion = 1;

  final Set<String> fingerprints;

  FindingBaseline(this.fingerprints);

  factory FindingBaseline.fromResult(AnalysisResult result) {
    return FindingBaseline(
      AnalysisFinding.fromResult(
        result,
      ).map((finding) => finding.fingerprint).toSet(),
    );
  }

  static Future<FindingBaseline> load(String path) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await File(path).readAsString());
    } on FormatException catch (error) {
      throw FormatException('Invalid Hyena baseline: ${error.message}');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != currentVersion ||
        decoded['fingerprints'] is! List) {
      throw const FormatException(
        'Invalid Hyena baseline: expected version 1 and a fingerprints list.',
      );
    }
    final values = decoded['fingerprints'] as List;
    if (values.any((value) => value is! String)) {
      throw const FormatException(
        'Invalid Hyena baseline: every fingerprint must be a string.',
      );
    }
    return FindingBaseline(values.cast<String>().toSet());
  }

  Future<void> write(String path) async {
    final sorted = fingerprints.toList()..sort();
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert({'version': currentVersion, 'fingerprints': sorted});
    await File(path).writeAsString('$content\n');
  }

  AnalysisResult apply(AnalysisResult result) {
    final rootPath = analysisRootForTarget(result.targetPath);
    return _apply(result, rootPath);
  }

  AnalysisResult _apply(AnalysisResult result, String rootPath) {
    if (result.isWorkspace) {
      return AnalysisResult(
        targetPath: result.targetPath,
        duration: result.duration,
        packageName: result.packageName,
        packageResults: result.packageResults
            .map((packageResult) => _apply(packageResult, rootPath))
            .toList(),
      );
    }
    final deadCodeReport = result.deadCodeReport;
    final filteredDeadCode = deadCodeReport == null
        ? null
        : DeadCodeReport(
            unusedEntities: deadCodeReport.unusedEntities
                .where(
                  (entity) => !fingerprints.contains(
                    AnalysisFinding.forDeadCode(
                      entity,
                      rootPath: rootPath,
                    ).fingerprint,
                  ),
                )
                .toList(),
            totalDeclarations: deadCodeReport.totalDeclarations,
            analyzedAt: deadCodeReport.analyzedAt,
          );

    final complexityReport = result.complexityReport;
    final filteredComplexity = complexityReport == null
        ? null
        : _applyComplexityBaseline(complexityReport, rootPath);

    return AnalysisResult(
      deadCodeReport: filteredDeadCode,
      complexityReport: filteredComplexity,
      targetPath: result.targetPath,
      duration: result.duration,
      packageName: result.packageName,
    );
  }

  ComplexityReport _applyComplexityBaseline(
    ComplexityReport report,
    String rootPath,
  ) {
    final files = report.files.map((file) {
      final functions = file.functions.map((metrics) {
        final suppressed = {...metrics.suppressedRules};
        _suppressComplexityRule(
          suppressed,
          metrics,
          ruleId: FindingRule.cyclomaticComplexity,
          threshold: report.cyclomaticThreshold,
          value: metrics.cyclomaticComplexity,
          isViolation:
              metrics.cyclomaticComplexity > report.cyclomaticThreshold,
          rootPath: rootPath,
        );
        _suppressComplexityRule(
          suppressed,
          metrics,
          ruleId: FindingRule.maxNesting,
          threshold: report.maxNestingLevel,
          value: metrics.maxNestingLevel,
          isViolation: metrics.maxNestingLevel > report.maxNestingLevel,
          rootPath: rootPath,
        );
        _suppressComplexityRule(
          suppressed,
          metrics,
          ruleId: FindingRule.maxParameters,
          threshold: report.maxParameters,
          value: metrics.parameterCount,
          isViolation: metrics.parameterCount > report.maxParameters,
          rootPath: rootPath,
        );
        return metrics.copyWith(suppressedRules: suppressed);
      }).toList();
      return FileMetrics(
        filePath: file.filePath,
        totalLines: file.totalLines,
        codeLines: file.codeLines,
        commentLines: file.commentLines,
        blankLines: file.blankLines,
        functions: functions,
      );
    }).toList();
    return ComplexityReport(
      files: files,
      cyclomaticThreshold: report.cyclomaticThreshold,
      maxNestingLevel: report.maxNestingLevel,
      maxParameters: report.maxParameters,
      analyzedAt: report.analyzedAt,
    );
  }

  void _suppressComplexityRule(
    Set<String> suppressed,
    FunctionMetrics metrics, {
    required String ruleId,
    required int threshold,
    required int value,
    required bool isViolation,
    required String rootPath,
  }) {
    if (!isViolation || suppressed.contains(ruleId)) return;
    final finding = AnalysisFinding.forComplexity(
      metrics,
      ruleId: ruleId,
      threshold: threshold,
      value: value,
      rootPath: rootPath,
    );
    if (fingerprints.contains(finding.fingerprint)) suppressed.add(ruleId);
  }
}
