import 'dead_code_report.dart';
import 'complexity_metrics.dart';

class AnalysisResult {
  final DeadCodeReport? deadCodeReport;
  final ComplexityReport? complexityReport;
  final String targetPath;
  final Duration duration;

  AnalysisResult({
    this.deadCodeReport,
    this.complexityReport,
    required this.targetPath,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'targetPath': targetPath,
    'duration': '${duration.inMilliseconds}ms',
    if (deadCodeReport != null) 'deadCode': deadCodeReport!.toJson(),
    if (complexityReport != null) 'complexity': complexityReport!.toJson(),
  };
}
