import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('workspace analysis', () {
    late Directory workspace;

    setUp(() async {
      workspace = await _createWorkspace();
    });

    tearDown(() async {
      await workspace.delete(recursive: true);
    });

    test(
      'uses per-package config and never double-counts member files',
      () async {
        final result = await const AnalysisRunner().analyze(
          workspace.path,
          includeDeadCode: false,
        );

        expect(result.isWorkspace, isTrue);
        expect(result.packageAnalyses.map((analysis) => analysis.packageName), [
          'workspace_root',
          'first_package',
          'second_package',
        ]);

        final root = result.packageAnalyses.first;
        final first = result.packageAnalyses.elementAt(1);
        final second = result.packageAnalyses.elementAt(2);
        expect(root.complexityReport!.totalFiles, 1);
        expect(first.complexityReport!.totalFiles, 1);
        expect(second.complexityReport!.totalFiles, 1);
        expect(first.complexityReport!.highComplexityFunctions, hasLength(1));
        expect(second.complexityReport!.highComplexityFunctions, isEmpty);
        expect(
          root.complexityReport!.files.single.filePath,
          isNot(contains('${p.separator}packages${p.separator}')),
        );

        final json = result.toJson();
        expect((json['workspace'] as Map)['packageCount'], 3);
        expect(json['packages'], hasLength(3));
      },
    );

    test('CLI emits package-scoped JSON for a workspace root', () async {
      final output = <String>[];
      final exitCode = await runZoned(
        () => HyenaCommandRunner().run([
          'complexity',
          workspace.path,
          '--format=json',
        ]),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, message) => output.add(message),
        ),
      );

      expect(exitCode, 0);
      final json = jsonDecode(output.join('\n')) as Map<String, dynamic>;
      expect((json['workspace'] as Map)['packageCount'], 3);
      expect(
        (json['packages'] as List).map((entry) => (entry as Map)['package']),
        ['workspace_root', 'first_package', 'second_package'],
      );
    });

    test('CLI can apply an explicit config outside the workspace', () async {
      final config =
          File(
            p.join(
              workspace.parent.path,
              'hyena_config_${DateTime.now().microsecondsSinceEpoch}.yaml',
            ),
          )..writeAsStringSync('''
hyena:
  complexity:
    cyclomatic_threshold: 0
''');
      addTearDown(() => config.delete());
      final output = <String>[];

      final exitCode = await runZoned(
        () => HyenaCommandRunner().run([
          'complexity',
          workspace.path,
          '--config=${config.path}',
          '--format=json',
        ]),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, message) => output.add(message),
        ),
      );

      expect(exitCode, 0);
      final json = jsonDecode(output.join('\n')) as Map<String, dynamic>;
      final packages = (json['packages'] as List).cast<Map>();
      for (final package in packages) {
        final complexity = package['complexity'] as Map;
        final summary = complexity['summary'] as Map;
        expect(summary['thresholdViolations'], greaterThan(0));
      }
    });

    test('discovers nested workspace members', () async {
      final first = Directory(p.join(workspace.path, 'packages', 'first'));
      File(p.join(first.path, 'pubspec.yaml')).writeAsStringSync('''
name: first_package
resolution: workspace
environment:
  sdk: ^3.10.0
workspace:
  - nested
''');
      final nested = Directory(p.join(first.path, 'nested', 'lib'))
        ..createSync(recursive: true);
      File(p.join(first.path, 'nested', 'pubspec.yaml')).writeAsStringSync('''
name: nested_package
resolution: workspace
environment:
  sdk: ^3.10.0
''');
      File(
        p.join(nested.path, 'nested.dart'),
      ).writeAsStringSync('void nestedFunction() {}');

      final result = await const AnalysisRunner().analyze(
        workspace.path,
        includeDeadCode: false,
      );

      expect(
        result.packageAnalyses.map((analysis) => analysis.packageName),
        contains('nested_package'),
      );
      expect(
        result.packageAnalyses
            .singleWhere((analysis) => analysis.packageName == 'first_package')
            .complexityReport!
            .totalFiles,
        1,
      );
    });

    test('supports glob workspace entries', () async {
      File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
environment:
  sdk: ^3.10.0
workspace:
  - packages/*
''');

      final result = await const AnalysisRunner().analyze(
        workspace.path,
        includeDeadCode: false,
      );

      expect(result.packageAnalyses.map((analysis) => analysis.packageName), [
        'workspace_root',
        'first_package',
        'second_package',
      ]);
    });

    test(
      'runs resolved dead-code analysis within each package boundary',
      () async {
        final pubGet = await Process.run(Platform.resolvedExecutable, [
          'pub',
          'get',
        ], workingDirectory: workspace.path);
        expect(pubGet.exitCode, 0, reason: pubGet.stderr as String);
        File(
          p.join(workspace.path, 'packages', 'first', 'lib', 'first.dart'),
        ).writeAsStringSync('void _unusedFirst() {}');
        File(
          p.join(workspace.path, 'packages', 'second', 'lib', 'second.dart'),
        ).writeAsStringSync('void _unusedSecond() {}');

        final result = await const AnalysisRunner().analyze(
          workspace.path,
          includeComplexity: false,
        );

        final first = result.packageAnalyses.singleWhere(
          (analysis) => analysis.packageName == 'first_package',
        );
        final second = result.packageAnalyses.singleWhere(
          (analysis) => analysis.packageName == 'second_package',
        );
        expect(
          first.deadCodeReport!.unusedEntities.map((entity) => entity.name),
          contains('_unusedFirst'),
        );
        expect(
          second.deadCodeReport!.unusedEntities.map((entity) => entity.name),
          contains('_unusedSecond'),
        );
        expect(
          first.deadCodeReport!.unusedEntities.map((entity) => entity.name),
          isNot(contains('_unusedSecond')),
        );
      },
    );

    test('rejects duplicate workspace membership', () async {
      File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
environment:
  sdk: ^3.10.0
workspace:
  - packages/first
  - packages/first
''');

      await expectLater(
        const AnalysisRunner().analyze(workspace.path, includeDeadCode: false),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('more than once'),
          ),
        ),
      );
    });

    test('rejects members without workspace resolution', () async {
      File(
        p.join(workspace.path, 'packages', 'first', 'pubspec.yaml'),
      ).writeAsStringSync('''
name: first_package
environment:
  sdk: ^3.10.0
''');

      await expectLater(
        const AnalysisRunner().analyze(workspace.path, includeDeadCode: false),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('resolution: workspace'),
          ),
        ),
      );
    });

    test('rejects duplicate package names and missing members', () async {
      File(
        p.join(workspace.path, 'packages', 'second', 'pubspec.yaml'),
      ).writeAsStringSync('''
name: first_package
resolution: workspace
environment:
  sdk: ^3.10.0
''');
      await expectLater(
        const AnalysisRunner().analyze(workspace.path, includeDeadCode: false),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('name first_package is duplicated'),
          ),
        ),
      );

      File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
environment:
  sdk: ^3.10.0
workspace:
  - packages/missing
''');
      await expectLater(
        const AnalysisRunner().analyze(workspace.path, includeDeadCode: false),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });

    test('rejects workspace members outside the workspace root', () async {
      File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
environment:
  sdk: ^3.10.0
workspace:
  - ../outside
''');
      final outside = Directory(p.join(workspace.parent.path, 'outside'))
        ..createSync();
      addTearDown(() async {
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      File(p.join(outside.path, 'pubspec.yaml')).writeAsStringSync('''
name: outside
environment:
  sdk: ^3.10.0
''');

      await expectLater(
        const AnalysisRunner().analyze(workspace.path, includeDeadCode: false),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'rejects workspace member symlinks outside the workspace root',
      () async {
        final outside = await Directory.systemTemp.createTemp(
          'hyena_workspace_outside_',
        );
        addTearDown(() => outside.delete(recursive: true));
        File(p.join(outside.path, 'pubspec.yaml')).writeAsStringSync('''
name: outside
resolution: workspace
environment:
  sdk: ^3.10.0
''');
        await Link(
          p.join(workspace.path, 'packages', 'linked'),
        ).create(outside.path);
        File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
environment:
  sdk: ^3.10.0
workspace:
  - packages/linked
''');

        await expectLater(
          const AnalysisRunner().analyze(
            workspace.path,
            includeDeadCode: false,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('outside the workspace root'),
            ),
          ),
        );
      },
      skip: Platform.isWindows
          ? 'Symlink creation may require privileges'
          : false,
    );
  });
}

Future<Directory> _createWorkspace() async {
  final workspace = await Directory.systemTemp.createTemp('hyena_workspace_');
  File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
publish_to: none
environment:
  sdk: ^3.10.0
workspace:
  - packages/first
  - packages/second
''');
  File(p.join(workspace.path, 'hyena.yaml')).writeAsStringSync('''
hyena:
  complexity:
    cyclomatic_threshold: 5
''');
  final tool = Directory(p.join(workspace.path, 'tool'))..createSync();
  File(p.join(tool.path, 'root.dart')).writeAsStringSync('''
void rootFunction(bool enabled) {
  if (enabled) print('root');
}
''');

  for (final name in ['first', 'second']) {
    final package = Directory(p.join(workspace.path, 'packages', name));
    final lib = Directory(p.join(package.path, 'lib'))
      ..createSync(recursive: true);
    File(p.join(package.path, 'pubspec.yaml')).writeAsStringSync('''
name: ${name}_package
resolution: workspace
environment:
  sdk: ^3.10.0
''');
    File(p.join(lib.path, '$name.dart')).writeAsStringSync('''
void ${name}Function(bool enabled) {
  if (enabled) print('$name');
}
''');
  }
  File(
    p.join(workspace.path, 'packages', 'first', 'hyena.yaml'),
  ).writeAsStringSync('''
hyena:
  complexity:
    cyclomatic_threshold: 1
''');
  return workspace;
}
