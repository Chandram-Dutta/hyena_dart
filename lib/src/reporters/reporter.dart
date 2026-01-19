import '../models/analysis_result.dart';

abstract class Reporter {
  Future<String> generate(AnalysisResult result);
}
