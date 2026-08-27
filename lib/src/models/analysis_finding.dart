import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'analysis_result.dart';
import 'code_entity.dart';
import 'complexity_metrics.dart';

abstract final class FindingRule {
  static const deadCode = 'dead-code';
  static const cyclomaticComplexity = ComplexityRule.cyclomaticComplexity;
  static const maxNesting = ComplexityRule.maxNesting;
  static const maxParameters = ComplexityRule.maxParameters;
}

class AnalysisFinding {
  final String category;
  final String ruleId;
  final String message;
  final String filePath;
  final String relativePath;
  final int line;
  final int? column;
  final String symbol;
  final String symbolType;
  final String? fingerprintSymbol;
  final Map<String, Object> properties;

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

  String get fingerprint => jsonEncode([
    category,
    ruleId,
    relativePath,
    symbolType,
    fingerprintSymbol ?? symbol,
  ]);

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

String analysisRootForTarget(String targetPath) {
  final absoluteTarget = p.absolute(targetPath);
  var directory = FileSystemEntity.isFileSync(absoluteTarget)
      ? File(absoluteTarget).parent
      : Directory(absoluteTarget);
  final fallbackRoot = directory.path;
  while (true) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      return p.normalize(directory.path);
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return p.normalize(fallbackRoot);
    directory = parent;
  }
}

String relativeFindingPath(String filePath, String rootPath) {
  final relative = p.relative(p.absolute(filePath), from: rootPath);
  return p.posix.joinAll(p.split(relative));
}
