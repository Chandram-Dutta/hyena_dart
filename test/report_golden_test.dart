import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:test/test.dart';

void main() {
  final result = _goldenResult();
  final reports = <String, Future<String> Function()>{
    'console.txt': () => ConsoleReporter(useColors: false).generate(result),
    'report.json': () => JsonReporter().generate(result),
    'report.md': () => MarkdownReporter().generate(result),
    'report.html': () => HtmlReporter().generate(result),
    'report.sarif': () => SarifReporter().generate(result),
  };

  for (final entry in reports.entries) {
    test('${entry.key} stays compatible with its golden', () async {
      final golden = await File('test/goldens/${entry.key}').readAsString();
      expect(
        _normalize(entry.key, await entry.value()),
        _normalize(entry.key, golden),
      );
    });
  }
}

String _normalize(String name, String value) {
  var normalized = value
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+(?=\n)'), '')
      .replaceFirst(RegExp(r'\n*$'), '\n');
  if (name == 'report.html') {
    normalized = normalized.replaceFirst(
      RegExp(r'<style>.*?</style>', dotAll: true),
      '<style>\n[report stylesheet]\n  </style>',
    );
  }
  return normalized;
}

AnalysisResult _goldenResult() {
  const workspacePath = '/workspace';
  const packagePath = '$workspacePath/packages/example';
  const filePath = '$packagePath/lib/example.dart';
  final analyzedAt = DateTime.utc(2026, 8, 27, 12, 0);
  final function = FunctionMetrics(
    name: 'complexThing',
    parentClass: 'Example',
    filePath: filePath,
    line: 10,
    cyclomaticComplexity: 3,
    linesOfCode: 4,
    maxNestingLevel: 2,
    parameterCount: 2,
    halsteadVolume: 32,
  );
  final packageResult = AnalysisResult(
    targetPath: packagePath,
    duration: const Duration(milliseconds: 7),
    packageName: 'example',
    deadCodeReport: DeadCodeReport(
      analyzedAt: analyzedAt,
      totalDeclarations: 2,
      unusedEntities: [
        CodeEntity(
          name: 'unusedHelper',
          type: EntityType.function,
          filePath: filePath,
          line: 3,
          column: 1,
          isPublic: true,
        ),
      ],
    ),
    complexityReport: ComplexityReport(
      analyzedAt: analyzedAt,
      cyclomaticThreshold: 1,
      maxNestingLevel: 1,
      maxParameters: 1,
      files: [
        FileMetrics(
          filePath: filePath,
          totalLines: 12,
          codeLines: 9,
          commentLines: 1,
          blankLines: 2,
          functions: [function],
        ),
      ],
    ),
  );
  return AnalysisResult(
    targetPath: workspacePath,
    duration: const Duration(milliseconds: 42),
    packageResults: [packageResult],
  );
}
