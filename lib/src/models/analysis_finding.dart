import 'dart:convert';

import 'analysis_path.dart';
import 'analysis_result.dart';
import 'code_entity.dart';
import 'complexity_metrics.dart';

/// Rule identifiers used by [AnalysisFinding.ruleId].
abstract final class FindingRule {
  /// An unused declaration.
  static const deadCode = 'dead-code';

  /// See [ComplexityRule.cyclomaticComplexity].
  static const cyclomaticComplexity = ComplexityRule.cyclomaticComplexity;

  /// See [ComplexityRule.maxNesting].
  static const maxNesting = ComplexityRule.maxNesting;

  /// See [ComplexityRule.maxParameters].
  static const maxParameters = ComplexityRule.maxParameters;
}

/// A single, format-independent issue reported by an analysis.
///
/// Baselines, SARIF output and `--fail-on` all work on findings.
class AnalysisFinding {
  /// Broad category: `dead-code` or `complexity`.
  final String category;

  /// The specific rule that was violated; one of the [FindingRule] constants.
  final String ruleId;

  /// Human-readable description of the issue.
  final String message;

  /// Absolute path of the affected file.
  final String filePath;

  /// Path of the affected file relative to the analysis root, using `/`
  /// separators.
  final String relativePath;

  /// 1-based line of the issue.
  final int line;

  /// 1-based column of the issue, if known.
  final int? column;

  /// Qualified name of the affected declaration.
  final String symbol;

  /// Kind of the affected declaration: `function` for complexity findings,
  /// or an [EntityType] name for dead code.
  final String symbolType;

  /// Symbol name used in [fingerprint] instead of [symbol], if set.
  final String? fingerprintSymbol;

  /// Extra rule-specific data, such as the measured `value` and `threshold`.
  final Map<String, Object> properties;

  /// Creates a finding.
  AnalysisFinding({
    required this.category,
    required this.ruleId,
    required this.message,
    required this.filePath,
    required this.relativePath,
    required this.line,
    this.column,
    required this.symbol,
    required this.symbolType,
    this.fingerprintSymbol,
    this.properties = const {},
  });

  /// A stable identifier for this finding that ignores line and column, so it
  /// survives unrelated edits. Stored in `FindingBaseline` files.
  String get fingerprint => jsonEncode([
    category,
    ruleId,
    relativePath,
    symbolType,
    fingerprintSymbol ?? symbol,
  ]);

  /// Collects every finding in [result], including all workspace packages.
  ///
  /// Relative paths are computed against [rootPath], which defaults to the
  /// package root containing [AnalysisResult.targetPath].
  static List<AnalysisFinding> fromResult(
    AnalysisResult result, {
    String? rootPath,
  }) {
    final analysisRoot = rootPath ?? analysisRootForTarget(result.targetPath);
    if (result.isWorkspace) {
      return result.packageResults
          .expand(
            (packageResult) =>
                fromResult(packageResult, rootPath: analysisRoot),
          )
          .toList();
    }
    final findings = <AnalysisFinding>[];
    final deadCodeReport = result.deadCodeReport;
    if (deadCodeReport != null) {
      findings.addAll(
        deadCodeReport.unusedEntities.map(
          (entity) => forDeadCode(entity, rootPath: analysisRoot),
        ),
      );
    }

    final complexityReport = result.complexityReport;
    if (complexityReport != null) {
      findings.addAll(
        complexityReport.highComplexityFunctions.map(
          (metrics) => forComplexity(
            metrics,
            ruleId: FindingRule.cyclomaticComplexity,
            threshold: complexityReport.cyclomaticThreshold,
            value: metrics.cyclomaticComplexity,
            rootPath: analysisRoot,
          ),
        ),
      );
      findings.addAll(
        complexityReport.highNestingFunctions.map(
          (metrics) => forComplexity(
            metrics,
            ruleId: FindingRule.maxNesting,
            threshold: complexityReport.maxNestingLevel,
            value: metrics.maxNestingLevel,
            rootPath: analysisRoot,
          ),
        ),
      );
      findings.addAll(
        complexityReport.highParameterFunctions.map(
          (metrics) => forComplexity(
            metrics,
            ruleId: FindingRule.maxParameters,
            threshold: complexityReport.maxParameters,
            value: metrics.parameterCount,
            rootPath: analysisRoot,
          ),
        ),
      );
    }
    return findings;
  }

  /// Creates the finding for an unused [entity], with its path relative to
  /// [rootPath].
  static AnalysisFinding forDeadCode(
    CodeEntity entity, {
    required String rootPath,
  }) {
    return AnalysisFinding(
      category: FindingRule.deadCode,
      ruleId: FindingRule.deadCode,
      message: 'Unused ${entity.typeLabel} ${entity.fullName}',
      filePath: entity.filePath,
      relativePath: relativeFindingPath(entity.filePath, rootPath),
      line: entity.line,
      column: entity.column,
      symbol: entity.fullName,
      symbolType: entity.type.name,
    );
  }

  /// Creates the finding for a function whose measured [value] for [ruleId]
  /// exceeds [threshold], with its path relative to [rootPath].
  static AnalysisFinding forComplexity(
    FunctionMetrics metrics, {
    required String ruleId,
    required int threshold,
    required int value,
    required String rootPath,
  }) {
    final metric = switch (ruleId) {
      FindingRule.cyclomaticComplexity => 'Cyclomatic complexity',
      FindingRule.maxNesting => 'Nesting level',
      FindingRule.maxParameters => 'Parameter count',
      _ => ruleId,
    };
    return AnalysisFinding(
      category: 'complexity',
      ruleId: ruleId,
      message:
          '$metric for ${metrics.fullName} is $value (threshold: $threshold)',
      filePath: metrics.filePath,
      relativePath: relativeFindingPath(metrics.filePath, rootPath),
      line: metrics.line,
      symbol: metrics.fullName,
      symbolType: 'function',
      fingerprintSymbol: metrics.fingerprintName,
      properties: {'value': value, 'threshold': threshold},
    );
  }
}
