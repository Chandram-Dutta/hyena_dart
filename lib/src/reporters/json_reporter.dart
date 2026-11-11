import 'dart:convert';

import '../models/analysis_result.dart';
import 'reporter.dart';

/// Renders an [AnalysisResult] as JSON, using [AnalysisResult.toJson].
class JsonReporter implements Reporter {
  /// Whether to indent the output with two spaces.
  final bool prettyPrint;

  /// Creates a JSON reporter.
  JsonReporter({this.prettyPrint = true});

  @override
  Future<String> generate(AnalysisResult result) async {
    final encoder = prettyPrint
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(result.toJson());
  }
}
