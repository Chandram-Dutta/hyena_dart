import 'analysis_path.dart';
import 'dead_code_report.dart';
import 'complexity_metrics.dart';

/// The combined outcome of running Hyena on a target path.
///
/// For a workspace, [packageResults] holds one result per member package and
/// the top-level reports are `null`.
class AnalysisResult {
  /// Dead code results, or `null` if dead code analysis was not run.
  final DeadCodeReport? deadCodeReport;

  /// Complexity results, or `null` if complexity analysis was not run.
  final ComplexityReport? complexityReport;

  /// The file or directory that was analyzed.
  final String targetPath;

  /// How long the analysis took.
  final Duration duration;

  /// Name of the analyzed package, if known.
  final String? packageName;

  /// Per-package results when the target is a workspace; empty otherwise.
  final List<AnalysisResult> packageResults;

  /// Creates an analysis result.
  AnalysisResult({
    this.deadCodeReport,
    this.complexityReport,
    required this.targetPath,
    required this.duration,
    this.packageName,
    this.packageResults = const [],
  });

  /// Whether this result aggregates several workspace packages.
  bool get isWorkspace => packageResults.isNotEmpty;

  /// The single-package results: this result itself, or every nested package
  /// result for a workspace.
  Iterable<AnalysisResult> get packageAnalyses sync* {
    if (!isWorkspace) {
      yield this;
      return;
    }
    for (final result in packageResults) {
      yield* result.packageAnalyses;
    }
  }

  /// Serializes this result to JSON.
  ///
  /// Paths are emitted relative to [rootPath], which defaults to the package
  /// root containing [targetPath].
  Map<String, dynamic> toJson({String? rootPath}) {
    final analysisRoot = rootPath ?? analysisRootForTarget(targetPath);
    return {
      'targetPath': relativeAnalysisPath(targetPath, analysisRoot),
      'duration': '${duration.inMilliseconds}ms',
      if (packageName != null) 'package': packageName,
      if (isWorkspace) ...{
        'workspace': _workspaceSummary(),
        'packages': packageResults
            .map((result) => result.toJson(rootPath: analysisRoot))
            .toList(),
      },
      if (deadCodeReport != null)
        'deadCode': deadCodeReport!.toJson(rootPath: analysisRoot),
      if (complexityReport != null)
        'complexity': complexityReport!.toJson(rootPath: analysisRoot),
    };
  }

  Map<String, dynamic> _workspaceSummary() {
    final analyses = packageAnalyses.toList();
    final deadCode = analyses
        .map((result) => result.deadCodeReport)
        .whereType<DeadCodeReport>()
        .toList();
    final complexity = analyses
        .map((result) => result.complexityReport)
        .whereType<ComplexityReport>()
        .toList();
    return {
      'packageCount': analyses.length,
      if (deadCode.isNotEmpty)
        'deadCode': {
          'totalDeclarations': deadCode.fold<int>(
            0,
            (sum, report) => sum + report.totalDeclarations,
          ),
          'unusedDeclarations': deadCode.fold<int>(
            0,
            (sum, report) => sum + report.unusedCount,
          ),
        },
      if (complexity.isNotEmpty)
        'complexity': {
          'files': complexity.fold<int>(
            0,
            (sum, report) => sum + report.totalFiles,
          ),
          'functions': complexity.fold<int>(
            0,
            (sum, report) => sum + report.totalFunctions,
          ),
          'lines': complexity.fold<int>(
            0,
            (sum, report) => sum + report.totalLines,
          ),
          'thresholdViolations': complexity.fold<int>(
            0,
            (sum, report) => sum + report.thresholdViolations.length,
          ),
        },
    };
  }
}
