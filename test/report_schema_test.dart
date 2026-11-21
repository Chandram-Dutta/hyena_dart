import 'dart:convert';
import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final document =
      jsonDecode(File('schema/report.schema.json').readAsStringSync())
          as Map<String, dynamic>;
  final schema = JsonSchema.create(document);

  void validate(dynamic report) {
    final result = schema.validate(report);
    expect(result.isValid, isTrue, reason: result.errors.toString());
  }

  test('schema version matches the public reporter constant', () {
    expect(
      document['properties']['schemaVersion']['const'],
      JsonReporter.schemaVersion,
    );
    expect(schema.schemaVersion, SchemaVersion.draft2020_12);
  });

  test('golden validates and additive fields remain compatible', () {
    final golden =
        jsonDecode(File('test/goldens/report.json').readAsStringSync())
            as Map<String, dynamic>;
    validate(golden);
    validate({...golden, 'futureField': true});
  });

  test('invalid versions and missing nested required fields fail', () {
    final golden =
        jsonDecode(File('test/goldens/report.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(schema.validate({...golden, 'schemaVersion': 999}).isValid, isFalse);
    final package = (golden['packages'] as List).first as Map;
    (package['deadCode'] as Map).remove('skippedFiles');
    expect(schema.validate(golden).isValid, isFalse);
  });

  for (final workspace in [false, true]) {
    for (final mode in ['analyze', 'dead-code', 'complexity']) {
      test(
        '$mode ${workspace ? 'workspace' : 'package'} output validates',
        () async {
          final root = await Directory.systemTemp.createTemp('hyena_schema_');
          addTearDown(() => root.delete(recursive: true));
          File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: schema_fixture
environment:
  sdk: ^3.11.0
${workspace ? 'workspace: [member]' : ''}
''');
          void source(String path, String contents) {
            final file = File(p.join(root.path, path));
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(contents);
          }

          source('lib/good.dart', 'void unused() {}\nvoid main() {}\n');
          source('lib/broken.dart', 'void broken( {\n');
          if (workspace) {
            source('member/pubspec.yaml', '''
name: schema_member
resolution: workspace
environment:
  sdk: ^3.11.0
''');
            source('member/lib/empty.dart', '');
          }
          final analysis = await const AnalysisRunner().analyze(
            root.path,
            includeDeadCode: mode != 'complexity',
            includeComplexity: mode != 'dead-code',
          );
          expect(analysis.isWorkspace, workspace);
          expect(analysis.skippedFiles, isNotEmpty);
          for (final prettyPrint in [true, false]) {
            final output = await JsonReporter(
              prettyPrint: prettyPrint,
            ).generate(analysis);
            final report = jsonDecode(output) as Map<String, dynamic>;
            expect(report.keys.first, 'schemaVersion');
            validate(report);
            final packages = workspace ? report['packages'] as List : [report];
            for (final package in packages.cast<Map>()) {
              expect(package.containsKey('deadCode'), mode != 'complexity');
              expect(package.containsKey('complexity'), mode != 'dead-code');
            }
          }
        },
      );
    }
  }

  test('real CLI output validates', () async {
    final process = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/hyena_dart.dart',
      'analyze',
      'example',
      '--format=json',
    ]);
    expect(process.exitCode, 0, reason: process.stderr.toString());
    validate(jsonDecode(process.stdout as String));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
