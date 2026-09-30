import '../config/analyzer_config.dart';
import '../models/dead_code_report.dart';
import 'dead_code/reachability.dart';
import 'dead_code/symbol_collector.dart';
import 'dead_code/symbols.dart';

class DeadCodeAnalyzer {
  final AnalyzerConfig config;

  DeadCodeAnalyzer(this.config);

  Future<DeadCodeReport> analyze(
    String targetPath, {
    Iterable<String> excludedPaths = const [],
  }) async {
    final analysis = await DeadCodeSymbolCollector(
      config,
    ).collect(targetPath, excludedPaths: excludedPaths);
    return const DeadCodeReachability().buildReports([analysis]).single;
  }

  static Future<List<({DeadCodeReport report, Duration duration})>>
  analyzeWorkspace(
    List<
      ({
        String targetPath,
        AnalyzerConfig config,
        Iterable<String> excludedPaths,
      })
    >
    packages,
  ) async {
    final analyses = <DeadCodeSymbols>[];
    for (final package in packages) {
      analyses.add(
        await DeadCodeSymbolCollector(
          package.config,
        ).collect(package.targetPath, excludedPaths: package.excludedPaths),
      );
    }
    final reports = const DeadCodeReachability().buildReports(analyses);
    return [
      for (var index = 0; index < reports.length; index++)
        (report: reports[index], duration: analyses[index].duration),
    ];
  }
}
