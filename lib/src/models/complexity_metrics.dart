import 'dart:math' as math;

import 'analysis_path.dart';
import 'skipped_file.dart';

/// Rule identifiers for complexity thresholds.
///
/// These ids are used in findings, baselines and `// hyena:ignore <rule>`
/// source suppressions.
abstract final class ComplexityRule {
  /// Cyclomatic complexity exceeds [ComplexityReport.cyclomaticThreshold].
  static const cyclomaticComplexity = 'cyclomatic-complexity';

  /// Nesting depth exceeds [ComplexityReport.maxNestingLevel].
  static const maxNesting = 'max-nesting';

  /// Parameter count exceeds [ComplexityReport.maxParameters].
  static const maxParameters = 'max-parameters';
}

/// Complexity metrics for a single function, method, constructor or accessor.
class FunctionMetrics {
  /// The simple name of the function.
  final String name;

  /// Absolute path of the file that contains the function.
  final String filePath;

  /// 1-based line where the function is declared.
  final int line;

  /// McCabe cyclomatic complexity: 1 plus the number of decision points.
  final int cyclomaticComplexity;

  /// Number of source lines spanned by the function.
  final int linesOfCode;

  /// Deepest nesting level of control-flow blocks inside the function.
  final int maxNestingLevel;

  /// Number of declared parameters.
  final int parameterCount;

  /// Halstead volume, computed from operator and operand counts.
  final double halsteadVolume;

  /// Name of the enclosing type for members, or `null` for top-level
  /// functions.
  final String? parentClass;

  /// A stable symbol name used when fingerprinting findings for baselines, if
  /// it differs from [fullName].
  final String? fingerprintName;

  /// [ComplexityRule] ids that are suppressed for this function, either by a
  /// source comment or by a `FindingBaseline`.
  final Set<String> suppressedRules;

  /// Creates metrics for one function.
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
    this.fingerprintName,
    this.suppressedRules = const {},
  });

  /// The qualified name: `Parent.name` for members, otherwise [name].
  String get fullName => parentClass != null ? '$parentClass.$name' : name;

  /// Returns a copy of these metrics, optionally replacing [suppressedRules].
  FunctionMetrics copyWith({Set<String>? suppressedRules}) => FunctionMetrics(
    name: name,
    filePath: filePath,
    line: line,
    cyclomaticComplexity: cyclomaticComplexity,
    linesOfCode: linesOfCode,
    maxNestingLevel: maxNestingLevel,
    parameterCount: parameterCount,
    halsteadVolume: halsteadVolume,
    parentClass: parentClass,
    fingerprintName: fingerprintName,
    suppressedRules: suppressedRules ?? this.suppressedRules,
  );

  /// Maintainability index normalized to the range 0–100 (higher is better).
  ///
  /// Derived from [halsteadVolume], [cyclomaticComplexity] and [linesOfCode].
  double get maintainabilityIndex {
    final rawIndex =
        171 -
        5.2 * math.log(math.max(halsteadVolume, 1)) -
        0.23 * cyclomaticComplexity -
        16.2 * math.log(math.max(linesOfCode, 1));
    return (rawIndex * 100 / 171).clamp(0, 100);
  }

  /// Serializes these metrics to JSON.
  ///
  /// When [rootPath] is given, [filePath] is emitted relative to it.
  Map<String, dynamic> toJson({String? rootPath}) => {
    'name': fullName,
    'filePath': rootPath == null
        ? filePath
        : relativeAnalysisPath(filePath, rootPath),
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

/// Line counts and per-function metrics for a single source file.
class FileMetrics {
  /// Absolute path of the analyzed file.
  final String filePath;

  /// Total number of lines in the file.
  final int totalLines;

  /// Number of lines that contain code.
  final int codeLines;

  /// Number of lines that contain only comments.
  final int commentLines;

  /// Number of empty or whitespace-only lines.
  final int blankLines;

  /// Metrics for each function declared in the file.
  final List<FunctionMetrics> functions;

  /// Creates metrics for one file.
  FileMetrics({
    required this.filePath,
    required this.totalLines,
    required this.codeLines,
    required this.commentLines,
    required this.blankLines,
    required this.functions,
  });

  /// Mean cyclomatic complexity over [functions], or 0 if there are none.
  double get averageCyclomaticComplexity {
    if (functions.isEmpty) return 0;
    return functions
            .map((f) => f.cyclomaticComplexity)
            .reduce((a, b) => a + b) /
        functions.length;
  }

  /// Highest cyclomatic complexity among [functions], or 0 if there are none.
  int get maxCyclomaticComplexity {
    if (functions.isEmpty) return 0;
    return functions
        .map((f) => f.cyclomaticComplexity)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Serializes these metrics to JSON.
  ///
  /// When [rootPath] is given, [filePath] is emitted relative to it.
  Map<String, dynamic> toJson({String? rootPath}) => {
    'filePath': rootPath == null
        ? filePath
        : relativeAnalysisPath(filePath, rootPath),
    'totalLines': totalLines,
    'codeLines': codeLines,
    'commentLines': commentLines,
    'blankLines': blankLines,
    'averageCyclomaticComplexity': averageCyclomaticComplexity.toStringAsFixed(
      2,
    ),
    'maxCyclomaticComplexity': maxCyclomaticComplexity,
    'functions': functions.map((f) => f.toJson(rootPath: rootPath)).toList(),
  };
}

/// The result of a complexity analysis, together with the thresholds that
/// were applied.
class ComplexityReport {
  /// Metrics for every analyzed file.
  final List<FileMetrics> files;

  /// Functions with a cyclomatic complexity above this value are reported.
  final int cyclomaticThreshold;

  /// Functions nested deeper than this value are reported.
  final int maxNestingLevel;

  /// Functions with more parameters than this value are reported.
  final int maxParameters;

  /// When the analysis was performed.
  final DateTime analyzedAt;

  /// Files that could not be analyzed and were left out of this report.
  final List<SkippedFile> skippedFiles;

  /// Creates a complexity report.
  ///
  /// [analyzedAt] defaults to the current time.
  ComplexityReport({
    required this.files,
    this.cyclomaticThreshold = 20,
    this.maxNestingLevel = 5,
    this.maxParameters = 6,
    DateTime? analyzedAt,
    this.skippedFiles = const [],
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  /// Number of analyzed files.
  int get totalFiles => files.length;

  /// Number of analyzed functions across all files.
  int get totalFunctions => files.fold(0, (sum, f) => sum + f.functions.length);

  /// Total line count across all files.
  int get totalLines => files.fold(0, (sum, f) => sum + f.totalLines);

  /// Unsuppressed functions above [cyclomaticThreshold], most complex first.
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

  /// Unsuppressed functions nested deeper than [maxNestingLevel].
  List<FunctionMetrics> get highNestingFunctions => files
      .expand((f) => f.functions)
      .where(
        (f) =>
            f.maxNestingLevel > maxNestingLevel &&
            !f.suppressedRules.contains(ComplexityRule.maxNesting),
      )
      .toList();

  /// Unsuppressed functions with more than [maxParameters] parameters.
  List<FunctionMetrics> get highParameterFunctions => files
      .expand((f) => f.functions)
      .where(
        (f) =>
            f.parameterCount > maxParameters &&
            !f.suppressedRules.contains(ComplexityRule.maxParameters),
      )
      .toList();

  /// Functions that violate at least one unsuppressed threshold, most complex
  /// first.
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

  /// Serializes this report, including a summary section, to JSON.
  ///
  /// When [rootPath] is given, file paths are emitted relative to it.
  Map<String, dynamic> toJson({String? rootPath}) => {
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
    'files': files.map((f) => f.toJson(rootPath: rootPath)).toList(),
    'skippedFiles': skippedFiles
        .map((file) => file.toJson(rootPath: rootPath))
        .toList(),
  };
}
