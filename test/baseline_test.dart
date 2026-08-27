import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('hyena_baseline_');
    File(
      p.join(fixture.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: baseline_fixture\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  test('fingerprints remain stable when source lines move', () {
    final filePath = p.join(fixture.path, 'lib', 'sample.dart');
    final first = AnalysisFinding.forDeadCode(
      CodeEntity(
        name: 'unused',
        type: EntityType.function,
        filePath: filePath,
        line: 3,
        column: 1,
        isPublic: true,
      ),
      rootPath: fixture.path,
    );
    final moved = AnalysisFinding.forDeadCode(
      CodeEntity(
        name: 'unused',
        type: EntityType.function,
        filePath: filePath,
        line: 30,
        column: 5,
        isPublic: true,
      ),
      rootPath: fixture.path,
    );

    expect(first.fingerprint, moved.fingerprint);
  });

  test('writes and applies dead-code baselines', () async {
    final result = _result(fixture.path);
    final path = p.join(fixture.path, 'hyena-baseline.json');

    await FindingBaseline.fromResult(result).write(path);
    final json = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(json['version'], 1);

    final filtered = (await FindingBaseline.load(path)).apply(result);
    expect(filtered.deadCodeReport!.unusedEntities, isEmpty);
    expect(filtered.complexityReport!.thresholdViolations, isEmpty);
  });

  test('applies complexity baselines per rule', () {
    final result = _result(fixture.path);
    final cyclomaticFinding = AnalysisFinding.fromResult(result).singleWhere(
      (finding) => finding.ruleId == FindingRule.cyclomaticComplexity,
    );

    final filtered = FindingBaseline({
      cyclomaticFinding.fingerprint,
    }).apply(result);

    expect(filtered.complexityReport!.highComplexityFunctions, isEmpty);
    expect(filtered.complexityReport!.highNestingFunctions, isNotEmpty);
    expect(filtered.complexityReport!.highParameterFunctions, isNotEmpty);
  });

  test('CLI writes and consumes baseline files', () async {
    final source = File(p.join(fixture.path, 'sample.dart'))
      ..writeAsStringSync('void target() {}\n');
    final baselinePath = p.join(fixture.path, 'hyena-baseline.json');

    final writeResult = await _runCli([
      'complexity',
      source.path,
      '--threshold=0',
      '--write-baseline=$baselinePath',
      '--format=json',
    ]);
    expect(writeResult.exitCode, 0);
    expect(File(baselinePath).existsSync(), isTrue);

    final baselineResult = await _runCli([
      'complexity',
      source.path,
      '--threshold=0',
      '--baseline=$baselinePath',
      '--format=json',
    ]);
    final json = jsonDecode(baselineResult.output) as Map<String, dynamic>;
    final complexity = json['complexity'] as Map<String, dynamic>;
    final summary = complexity['summary'] as Map<String, dynamic>;
    expect(summary['thresholdViolations'], 0);

    final failingResult = await _runCli([
      'complexity',
      source.path,
      '--threshold=0',
      '--fail-on=complexity',
      '--format=json',
    ]);
    expect(failingResult.exitCode, 1);

    final passingResult = await _runCli([
      'complexity',
      source.path,
      '--threshold=0',
      '--baseline=$baselinePath',
      '--fail-on=complexity',
      '--format=json',
    ]);
    expect(passingResult.exitCode, 0);
  });
}

Future<({String output, int exitCode})> _runCli(List<String> arguments) async {
  final output = <String>[];
  final exitCode = await runZoned(
    () => HyenaCommandRunner().run(arguments),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, message) => output.add(message),
    ),
  );
  return (output: output.join('\n'), exitCode: exitCode ?? 0);
}

AnalysisResult _result(String rootPath) {
  final filePath = p.join(rootPath, 'lib', 'sample.dart');
  final metrics = FunctionMetrics(
    name: 'complexFunction',
    filePath: filePath,
    line: 10,
    cyclomaticComplexity: 5,
    linesOfCode: 10,
    maxNestingLevel: 3,
    parameterCount: 4,
  );
  return AnalysisResult(
    targetPath: rootPath,
    duration: Duration.zero,
    deadCodeReport: DeadCodeReport(
      totalDeclarations: 1,
      unusedEntities: [
        CodeEntity(
          name: 'unused',
          type: EntityType.function,
          filePath: filePath,
          line: 3,
          column: 1,
          isPublic: true,
        ),
      ],
    ),
    complexityReport: ComplexityReport(
      files: [
        FileMetrics(
          filePath: filePath,
          totalLines: 20,
          codeLines: 15,
          commentLines: 2,
          blankLines: 3,
          functions: [metrics],
        ),
      ],
      cyclomaticThreshold: 1,
      maxNestingLevel: 1,
      maxParameters: 1,
    ),
  );
}
