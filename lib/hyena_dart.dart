/// Static analysis for Dart and Flutter codebases: dead code detection and
/// complexity metrics.
///
/// This library exposes the analyzers, configuration, result models and
/// reporters behind the `hyena_dart` command-line tool so they can be used
/// programmatically.
///
/// * [DeadCodeAnalyzer] finds declarations that are never referenced and
///   produces a [DeadCodeReport].
/// * [ComplexityAnalyzer] computes per-function metrics such as cyclomatic
///   complexity, nesting depth and maintainability index, producing a
///   [ComplexityReport].
/// * [AnalysisRunner] runs either or both analyses over a single package or a
///   whole Dart workspace and returns an [AnalysisResult].
/// * [AnalyzerConfig] controls thresholds, exclusions and other options; it
///   can be loaded from `hyena.yaml` or the `hyena:` key of
///   `analysis_options.yaml`.
/// * [Reporter] implementations ([ConsoleReporter], [JsonReporter],
///   [MarkdownReporter], [HtmlReporter], [SarifReporter]) render an
///   [AnalysisResult] as text.
/// * [FindingBaseline] records known findings so that only new ones fail a
///   build.
///
/// ```dart
/// import 'package:hyena_dart/hyena_dart.dart';
///
/// Future<void> main() async {
///   final config = AnalyzerConfig(cyclomaticThreshold: 15);
///   final deadCode = await DeadCodeAnalyzer(config).analyze('lib');
///   print('Unused: ${deadCode.unusedCount}/${deadCode.totalDeclarations}');
/// }
/// ```
library;

export 'src/analyzer/dead_code_analyzer.dart';
export 'src/analyzer/complexity_analyzer.dart';
export 'src/analyzer/analysis_runner.dart';
export 'src/config/analyzer_config.dart';
export 'src/models/analysis_result.dart';
export 'src/models/analysis_finding.dart';
export 'src/models/code_entity.dart';
export 'src/models/complexity_metrics.dart';
export 'src/models/dead_code_report.dart';
export 'src/models/finding_baseline.dart';
export 'src/models/skipped_file.dart';
export 'src/reporters/reporter.dart';
export 'src/reporters/console_reporter.dart';
export 'src/reporters/json_reporter.dart';
export 'src/reporters/markdown_reporter.dart';
export 'src/reporters/html_reporter.dart';
export 'src/reporters/sarif_reporter.dart';
export 'src/version.dart';
