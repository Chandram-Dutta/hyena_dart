import '../models/analysis_result.dart';

/// Converts an [AnalysisResult] into a textual report format.
abstract class Reporter {
  /// Renders [result] and returns the report contents.
  Future<String> generate(AnalysisResult result);
}
