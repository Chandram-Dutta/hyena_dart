import 'dart:convert';

import '../models/analysis_result.dart';
import 'reporter.dart';

class JsonReporter implements Reporter {
  final bool prettyPrint;

  JsonReporter({this.prettyPrint = true});

  @override
  Future<String> generate(AnalysisResult result) async {
    final encoder = prettyPrint
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(result.toJson());
  }
}
