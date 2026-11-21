import 'dart:convert';

import '../models/analysis_result.dart';
import 'reporter.dart';

/// Renders an [AnalysisResult] as JSON, using [AnalysisResult.toJson].
class JsonReporter implements Reporter {
  /// Version of the CLI JSON report contract.
  static const schemaVersion = 1;

  /// Whether to indent the output with two spaces.
  final bool prettyPrint;

  /// Creates a JSON reporter.
  JsonReporter({this.prettyPrint = true});

  @override
  Future<String> generate(AnalysisResult result) async {
    final encoder = prettyPrint
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert({
      'schemaVersion': schemaVersion,
      ...result.toJson(),
    });
  }
}
