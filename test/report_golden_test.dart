import 'dart:convert';
import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:path/path.dart' as p;
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

  test(
    'all reports keep subdirectory and file targets project-relative',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'hyena_relative_reports_',
      );
      addTearDown(() => project.delete(recursive: true));
      File(
        p.join(project.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: relative_reports\n');
      final source = File(p.join(project.path, 'lib', 'example.dart'));
      source.parent.createSync();
      source.writeAsStringSync('void unused() {}\n');

      for (final (targetPath, expectedTarget) in [
        (source.parent.path, 'lib'),
        (source.path, 'lib/example.dart'),
      ]) {
        final result = _relativePathResult(targetPath, source.path);
        final outputs = {
          'console': await ConsoleReporter(useColors: false).generate(result),
          'json': await JsonReporter().generate(result),
          'markdown': await MarkdownReporter().generate(result),
          'html': await HtmlReporter().generate(result),
        };

        for (final entry in outputs.entries) {
          expect(entry.value, isNot(contains(project.path)), reason: entry.key);
          if (entry.key == 'html') {
            expect(
              entry.value,
              contains(expectedTarget.replaceAll('/', '&#47;')),
              reason: entry.key,
            );
            expect(
              entry.value,
              contains('lib&#47;example.dart'),
              reason: entry.key,
            );
          } else {
            expect(entry.value, contains(expectedTarget), reason: entry.key);
            expect(
              entry.value,
              contains('lib/example.dart'),
              reason: entry.key,
            );
          }
        }

        final json = jsonDecode(outputs['json']!) as Map<String, dynamic>;
        expect(json['targetPath'], expectedTarget);
      }
    },
  );
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

AnalysisResult _relativePathResult(String targetPath, String filePath) {
  final function = FunctionMetrics(
    name: 'unused',
    filePath: filePath,
    line: 1,
    cyclomaticComplexity: 2,
    linesOfCode: 1,
    maxNestingLevel: 0,
    parameterCount: 0,
  );
  return AnalysisResult(
    targetPath: targetPath,
    duration: Duration.zero,
    deadCodeReport: DeadCodeReport(
      totalDeclarations: 1,
      unusedEntities: [
        CodeEntity(
          name: 'unused',
          type: EntityType.function,
          filePath: filePath,
          line: 1,
          column: 1,
          isPublic: true,
        ),
      ],
    ),
    complexityReport: ComplexityReport(
      cyclomaticThreshold: 1,
      files: [
        FileMetrics(
          filePath: filePath,
          totalLines: 1,
          codeLines: 1,
          commentLines: 0,
          blankLines: 0,
          functions: [function],
        ),
      ],
    ),
  );
}
