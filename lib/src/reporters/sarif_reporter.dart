import 'dart:convert';

import '../models/analysis_finding.dart';
import '../models/analysis_result.dart';
import 'reporter.dart';

class SarifReporter implements Reporter {
  static const _ruleOrder = [
    FindingRule.deadCode,
    FindingRule.cyclomaticComplexity,
    FindingRule.maxNesting,
    FindingRule.maxParameters,
  ];

  @override
  Future<String> generate(AnalysisResult result) async {
    final findings = AnalysisFinding.fromResult(result);
    final sarif = <String, Object>{
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'Hyena Dart',
              'informationUri': 'https://github.com/Chandram-Dutta/hyena_dart',
              'rules': _ruleOrder.map(_rule).toList(),
            },
          },
          'results': findings.map(_result).toList(),
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(sarif);
  }

  Map<String, Object> _rule(String id) {
    final (name, description) = switch (id) {
      FindingRule.deadCode => (
        'Dead code',
        'A declaration is not reachable from an analyzed entry point.',
      ),
      FindingRule.cyclomaticComplexity => (
        'Cyclomatic complexity',
        'A function exceeds the configured cyclomatic complexity threshold.',
      ),
      FindingRule.maxNesting => (
        'Maximum nesting',
        'A function exceeds the configured nesting threshold.',
      ),
      FindingRule.maxParameters => (
        'Maximum parameters',
        'A function exceeds the configured parameter count threshold.',
      ),
      _ => (id, id),
    };
    return {
      'id': id,
      'name': name,
      'shortDescription': {'text': description},
      'defaultConfiguration': {'level': 'warning'},
    };
  }

  Map<String, Object> _result(AnalysisFinding finding) {
    final region = <String, Object>{'startLine': finding.line};
    final column = finding.column;
    if (column != null) region['startColumn'] = column;
    return {
      'ruleId': finding.ruleId,
      'ruleIndex': _ruleOrder.indexOf(finding.ruleId),
      'level': 'warning',
      'message': {'text': finding.message},
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': {
              'uri': Uri(path: finding.relativePath).toString(),
            },
            'region': region,
          },
        },
      ],
      'partialFingerprints': {'hyenaFingerprint/v1': finding.fingerprint},
      'properties': {
        'category': finding.category,
        'symbol': finding.symbol,
        'symbolType': finding.symbolType,
        ...finding.properties,
      },
    };
  }
}
