import 'dart:math' as math;

abstract final class ComplexityRule {
  static const cyclomaticComplexity = 'cyclomatic-complexity';
  static const maxNesting = 'max-nesting';
  static const maxParameters = 'max-parameters';
}

class FunctionMetrics {
  final String name;
  final String filePath;
  final int line;
  final int cyclomaticComplexity;
  final int linesOfCode;
  final int maxNestingLevel;
  final int parameterCount;
  final double halsteadVolume;
  final String? parentClass;
  final Set<String> suppressedRules;

  FunctionMetrics({
    required this.name,
    required this.filePath,
    required this.line,
    required this.cyclomaticComplexity,
    required this.linesOfCode,
    required this.maxNestingLevel,
    required this.parameterCount,
    this.halsteadVolume = 0,
    this.parentClass,
    this.suppressedRules = const {},
  });

  String get fullName => parentClass != null ? '$parentClass.$name' : name;

  double get maintainabilityIndex {
    final rawIndex =
        171 -
        5.2 * math.log(math.max(halsteadVolume, 1)) -
        0.23 * cyclomaticComplexity -
        16.2 * math.log(math.max(linesOfCode, 1));
    return (rawIndex * 100 / 171).clamp(0, 100);
  }

  Map<String, dynamic> toJson() => {
    'name': fullName,
    'filePath': filePath,
    'line': line,
    'cyclomaticComplexity': cyclomaticComplexity,
    'linesOfCode': linesOfCode,
    'maxNestingLevel': maxNestingLevel,
    'parameterCount': parameterCount,
    'halsteadVolume': halsteadVolume.toStringAsFixed(2),
    'maintainabilityIndex': maintainabilityIndex.toStringAsFixed(2),
    if (suppressedRules.isNotEmpty)
      'suppressedRules': suppressedRules.toList()..sort(),
  };
}

class FileMetrics {
  final String filePath;
  final int totalLines;
  final int codeLines;
  final int commentLines;
  final int blankLines;
  final List<FunctionMetrics> functions;

  FileMetrics({
    required this.filePath,
    required this.totalLines,
    required this.codeLines,
    required this.commentLines,
    required this.blankLines,
    required this.functions,
  });

  double get averageCyclomaticComplexity {
    if (functions.isEmpty) return 0;
    return functions
            .map((f) => f.cyclomaticComplexity)
            .reduce((a, b) => a + b) /
        functions.length;
  }

  int get maxCyclomaticComplexity {
    if (functions.isEmpty) return 0;
    return functions
        .map((f) => f.cyclomaticComplexity)
        .reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'totalLines': totalLines,
    'codeLines': codeLines,
    'commentLines': commentLines,
    'blankLines': blankLines,
    'averageCyclomaticComplexity': averageCyclomaticComplexity.toStringAsFixed(
      2,
    ),
    'maxCyclomaticComplexity': maxCyclomaticComplexity,
    'functions': functions.map((f) => f.toJson()).toList(),
  };
}

class ComplexityReport {
  final List<FileMetrics> files;
  final int cyclomaticThreshold;
  final int maxNestingLevel;
  final int maxParameters;
  final DateTime analyzedAt;

  ComplexityReport({
    required this.files,
    this.cyclomaticThreshold = 20,
    this.maxNestingLevel = 5,
    this.maxParameters = 6,
    DateTime? analyzedAt,
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  int get totalFiles => files.length;
  int get totalFunctions => files.fold(0, (sum, f) => sum + f.functions.length);
  int get totalLines => files.fold(0, (sum, f) => sum + f.totalLines);

  List<FunctionMetrics> get highComplexityFunctions {
    return files
        .expand((f) => f.functions)
        .where(
          (f) =>
              f.cyclomaticComplexity > cyclomaticThreshold &&
              !f.suppressedRules.contains(ComplexityRule.cyclomaticComplexity),
        )
        .toList()
      ..sort(
        (a, b) => b.cyclomaticComplexity.compareTo(a.cyclomaticComplexity),
      );
  }

  List<FunctionMetrics> get highNestingFunctions => files
      .expand((f) => f.functions)
      .where(
        (f) =>
            f.maxNestingLevel > maxNestingLevel &&
            !f.suppressedRules.contains(ComplexityRule.maxNesting),
      )
      .toList();

  List<FunctionMetrics> get highParameterFunctions => files
      .expand((f) => f.functions)
      .where(
        (f) =>
            f.parameterCount > maxParameters &&
            !f.suppressedRules.contains(ComplexityRule.maxParameters),
      )
      .toList();

  List<FunctionMetrics> get thresholdViolations {
    final violations = files
        .expand((f) => f.functions)
        .where(
          (f) =>
              (f.cyclomaticComplexity > cyclomaticThreshold &&
                  !f.suppressedRules.contains(
                    ComplexityRule.cyclomaticComplexity,
                  )) ||
              (f.maxNestingLevel > maxNestingLevel &&
                  !f.suppressedRules.contains(ComplexityRule.maxNesting)) ||
              (f.parameterCount > maxParameters &&
                  !f.suppressedRules.contains(ComplexityRule.maxParameters)),
        )
        .toList();
    violations.sort(
      (a, b) => b.cyclomaticComplexity.compareTo(a.cyclomaticComplexity),
    );
    return violations;
  }

  Map<String, dynamic> toJson() => {
    'analyzedAt': analyzedAt.toIso8601String(),
    'thresholds': {
      'cyclomaticComplexity': cyclomaticThreshold,
      'maxNestingLevel': maxNestingLevel,
      'maxParameters': maxParameters,
    },
    'summary': {
      'totalFiles': totalFiles,
      'totalFunctions': totalFunctions,
      'totalLines': totalLines,
      'highComplexityFunctions': highComplexityFunctions.length,
      'highNestingFunctions': highNestingFunctions.length,
      'highParameterFunctions': highParameterFunctions.length,
      'thresholdViolations': thresholdViolations.length,
    },
    'files': files.map((f) => f.toJson()).toList(),
  };
}
