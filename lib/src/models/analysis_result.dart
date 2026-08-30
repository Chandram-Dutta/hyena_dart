import 'analysis_path.dart';
import 'dead_code_report.dart';
import 'complexity_metrics.dart';

class AnalysisResult {
  final DeadCodeReport? deadCodeReport;
  final ComplexityReport? complexityReport;
  final String targetPath;
  final Duration duration;
  final String? packageName;
  final List<AnalysisResult> packageResults;

  AnalysisResult({
    this.deadCodeReport,
    this.complexityReport,
    required this.targetPath,
    required this.duration,
    this.packageName,
    this.packageResults = const [],
  });

  bool get isWorkspace => packageResults.isNotEmpty;

  Iterable<AnalysisResult> get packageAnalyses sync* {
    if (!isWorkspace) {
      yield this;
      return;
    }
    for (final result in packageResults) {
      yield* result.packageAnalyses;
    }
  }

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
