import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart' show NotPathOfUriResult;
import 'package:hyena_dart/hyena_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates a small package with a healthy `lib/lib.dart` plus [files] (paths
/// relative to `lib/`) and returns the absolute, normalized package root.
Future<String> _createPackage(Map<String, String> files) async {
  final root = await Directory.systemTemp.createTemp('hyena_skipped_');
  addTearDown(() => root.delete(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: hyena_skipped_fixture
environment:
  sdk: ^3.10.0
''');
  final sources = {
    'lib.dart': '''
void helper() {}
void unused() {}
void main() {}
''',
    ...files,
  };
  for (final MapEntry(key: path, value: source) in sources.entries) {
    final file = File(p.join(root.path, 'lib', path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  }
  return p.normalize(p.absolute(root.path));
}

String _lib(String root, String file) => p.join(root, 'lib', file);

void main() {
  group('DeadCodeAnalyzer skipped files', () {
    test('skips a file with analysis errors and keeps analyzing', () async {
      final root = await _createPackage({
        'broken.dart': '''
import 'lib.dart';
import 'package:not_installed/not_installed.dart';

void callsHelper() => helper();
''',
      });

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(),
      ).analyze(p.join(root, 'lib'));

      final unused = report.unusedEntities.map((e) => e.name).toSet();
      expect(unused, contains('unused'));
      expect(
        unused,
        isNot(contains('helper')),
        reason: 'references from a skipped file still keep code alive',
      );
      expect(
        unused,
        isNot(contains('callsHelper')),
        reason: 'declarations in a skipped file are not reported',
      );
      final skipped = report.skippedFiles.single;
      expect(skipped.filePath, _lib(root, 'broken.dart'));
      expect(skipped.reason, contains('analysis error'));
      expect(skipped.reason, contains('line 2'));
      expect(skipped.reason, contains('not_installed'));
    });

    test('skips a file whose resolution throws', () async {
      final root = await _createPackage({'other.dart': 'void other() {}'});
      final throwing = _lib(root, 'other.dart');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(),
        resolveUnit: (session, path) {
          if (path == throwing) throw StateError('resolver exploded');
          return session.getResolvedUnit(path);
        },
      ).analyze(p.join(root, 'lib'));

      expect(report.unusedEntities.map((e) => e.name), contains('unused'));
      expect(
        report.unusedEntities.map((e) => e.name),
        isNot(contains('other')),
      );
      final skipped = report.skippedFiles.single;
      expect(skipped.filePath, throwing);
      expect(skipped.reason, contains('resolver exploded'));
    });

    test('skips a path the analyzer session rejects', () async {
      final root = await _createPackage({'other.dart': 'void other() {}'});
      final unresolvable = _lib(root, 'other.dart');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(),
        resolveUnit: (session, path) {
          // The real analyzer session refuses non-normalized paths.
          if (path == unresolvable) {
            return session.getResolvedUnit(
              p.join(p.dirname(path), '.', p.basename(path)),
            );
          }
          return session.getResolvedUnit(path);
        },
      ).analyze(p.join(root, 'lib'));

      expect(report.unusedEntities.map((e) => e.name), contains('unused'));
      final skipped = report.skippedFiles.single;
      expect(skipped.filePath, unresolvable);
      expect(skipped.reason, startsWith('Analyzer failed:'));
      expect(skipped.reason, contains('normalized'));
    });

    test('skips a file the analyzer cannot resolve', () async {
      final root = await _createPackage({'other.dart': 'void other() {}'});
      final unresolvable = _lib(root, 'other.dart');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(),
        resolveUnit: (session, path) async => path == unresolvable
            ? NotPathOfUriResult()
            : await session.getResolvedUnit(path),
      ).analyze(p.join(root, 'lib'));

      expect(report.unusedEntities.map((e) => e.name), contains('unused'));
      expect(
        report.unusedEntities.map((e) => e.name),
        isNot(contains('other')),
      );
      expect(report.skippedFiles.single.filePath, unresolvable);
      expect(
        report.skippedFiles.single.reason,
        'The analyzer could not resolve this file '
        '(path does not match its URI).',
      );
    });
  });

  group('ComplexityAnalyzer skipped files', () {
    test('uses latest syntax without a package config', () async {
      final root = await _createPackage({
        'identity.dart': 'int identity({final int value = 1}) => value;',
      });

      final report = await ComplexityAnalyzer(AnalyzerConfig()).analyze(root);

      expect(report.skippedFiles.single.filePath, _lib(root, 'identity.dart'));
      expect(report.skippedFiles.single.reason, contains('syntax error'));
    });

    test('handles empty and invalid injected source', () async {
      final root = await _createPackage({
        'identity.dart': 'void original() {}',
      });
      for (final source in ['', 'void broken( {']) {
        final report = await ComplexityAnalyzer(
          AnalyzerConfig(),
          readSource: (path) async => path == _lib(root, 'identity.dart')
              ? source
              : File(path).readAsString(),
        ).analyze(root);

        if (source.isEmpty) {
          expect(report.skippedFiles, isEmpty);
          expect(
            report.files
                .singleWhere(
                  (file) => file.filePath == _lib(root, 'identity.dart'),
                )
                .functions,
            isEmpty,
          );
        } else {
          expect(report.skippedFiles.single.reason, contains('syntax error'));
        }
      }
    });

    test('analyzes injected source with a language version override', () async {
      final root = await _createPackage({
        'identity.dart': 'void original() {}',
      });
      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
        readSource: (path) async => path == _lib(root, 'identity.dart')
            ? '// @dart=3.0\nint identity({final int value = 1}) => value;'
            : File(path).readAsString(),
      ).analyze(root);

      expect(report.skippedFiles, isEmpty);
      final metrics = report.files
          .singleWhere((file) => file.filePath == _lib(root, 'identity.dart'))
          .functions
          .single;
      expect(metrics.name, 'identity');
      expect(metrics.cyclomaticComplexity, 1);
      expect(metrics.parameterCount, 1);
    });

    test('respects a per-file language version override', () async {
      final root = await _createPackage({
        'identity.dart': '''
// @dart=3.0
int identity({final int value = 1}) => value;
''',
      });

      final report = await ComplexityAnalyzer(AnalyzerConfig()).analyze(root);

      expect(report.skippedFiles, isEmpty);
      expect(
        report.files
            .singleWhere((file) => file.filePath == _lib(root, 'identity.dart'))
            .functions
            .single
            .name,
        'identity',
      );
    });

    test('uses the package_config language version', () async {
      final root = await _createPackage({
        'identity.dart': 'int identity({final int value = 1}) => value;',
      });
      final packageConfig = File(
        p.join(root, '.dart_tool', 'package_config.json'),
      );
      packageConfig.parent.createSync();
      packageConfig.writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'hyena_skipped_fixture',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.0',
            },
          ],
        }),
      );

      final report = await ComplexityAnalyzer(AnalyzerConfig()).analyze(root);

      expect(report.skippedFiles, isEmpty);
      expect(report.totalFunctions, 4);
    });

    test('uses the package language version for complexity metrics', () async {
      final root = await _createPackage({
        'identity.dart': 'int identity({final int value = 1}) => value;',
      });
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync('''
name: hyena_skipped_fixture
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final pubGet = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: root);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');

      final report = await ComplexityAnalyzer(AnalyzerConfig()).analyze(root);

      expect(report.skippedFiles, isEmpty);
      final metrics = report.files
          .singleWhere((file) => file.filePath == _lib(root, 'identity.dart'))
          .functions
          .single;
      expect(metrics.name, 'identity');
      expect(metrics.cyclomaticComplexity, 1);
      expect(metrics.parameterCount, 1);
    });

    test('skips a file with syntax errors and keeps analyzing', () async {
      final root = await _createPackage({'broken.dart': 'void broken( {'});

      final report = await ComplexityAnalyzer(AnalyzerConfig()).analyze(root);

      expect(report.files.map((file) => file.filePath), [
        _lib(root, 'lib.dart'),
      ]);
      final skipped = report.skippedFiles.single;
      expect(skipped.filePath, _lib(root, 'broken.dart'));
      expect(skipped.reason, contains('syntax error'));
      expect(skipped.reason, contains('line 1'));
    });

    test('skips a file that cannot be decoded', () async {
      final root = await _createPackage({});
      File(
        _lib(root, 'latin1.dart'),
      ).writeAsBytesSync([...utf8.encode('// caf'), 0xE9, 0x0A]);

      final report = await ComplexityAnalyzer(AnalyzerConfig()).analyze(root);

      expect(report.totalFiles, 1);
      final skipped = report.skippedFiles.single;
      expect(skipped.filePath, _lib(root, 'latin1.dart'));
      expect(skipped.reason, startsWith('Could not read file'));
    });

    test('skips a file whose analysis throws', () async {
      final root = await _createPackage({'other.dart': 'void other() {}'});
      final throwing = _lib(root, 'other.dart');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
        readSource: (path) async {
          if (path == throwing) throw StateError('reader exploded');
          return File(path).readAsString();
        },
      ).analyze(root);

      expect(report.files.map((file) => file.filePath), [
        _lib(root, 'lib.dart'),
      ]);
      expect(report.skippedFiles.single.filePath, throwing);
      expect(report.skippedFiles.single.reason, contains('reader exploded'));
    });

    test('skips a file that disappears before it can be read', () async {
      final root = await _createPackage({'gone.dart': 'void gone() {}'});
      final vanishing = _lib(root, 'gone.dart');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
        readSource: (path) async {
          if (path == vanishing) File(path).deleteSync();
          return File(path).readAsString();
        },
      ).analyze(root);

      expect(report.totalFiles, 1);
      expect(report.skippedFiles.single.filePath, vanishing);
      expect(
        report.skippedFiles.single.reason,
        startsWith('Could not read file'),
      );
    });
  });

  group('AnalysisRunner skipped files', () {
    test('manual declaration-bearing reports are not all skipped', () {
      final result = AnalysisResult(
        targetPath: '/project',
        duration: Duration.zero,
        deadCodeReport: DeadCodeReport(
          unusedEntities: const [],
          totalDeclarations: 1,
          skippedFiles: const [
            SkippedFile(filePath: '/project/broken.dart', reason: 'broken'),
          ],
        ),
      );
      expect(result.deadCodeReport!.analyzedFileCount, 0);
      expect(result.allFilesSkipped, isFalse);
    });

    test(
      'counts empty analyzed files and preserves counts through baselines',
      () async {
        final root = await _createPackage({
          'lib.dart': '',
          'broken.dart': 'void broken( {',
        });
        final result = await const AnalysisRunner().analyze(root);
        expect(result.deadCodeReport!.analyzedFileCount, 1);
        expect(result.allFilesSkipped, isFalse);
        expect(
          FindingBaseline.fromResult(result).apply(result).allFilesSkipped,
          isFalse,
        );
        final workspace = AnalysisResult(
          targetPath: root,
          duration: Duration.zero,
          packageResults: [result],
        );
        expect(workspace.allFilesSkipped, isFalse);
        final json =
            jsonDecode(await SarifReporter().generate(workspace)) as Map;
        expect(
          json['runs'][0]['invocations'][0]['executionSuccessful'],
          isTrue,
        );
      },
    );

    test('reports skips from both analyzers without aborting', () async {
      final root = await _createPackage({'broken.dart': 'void broken( {'});

      final result = await const AnalysisRunner().analyze(root);

      expect(
        result.deadCodeReport!.unusedEntities.map((e) => e.name),
        unorderedEquals(['helper', 'unused']),
      );
      expect(result.complexityReport!.totalFiles, 1);
      expect(result.skippedFiles.map((file) => file.filePath), [
        _lib(root, 'broken.dart'),
        _lib(root, 'broken.dart'),
      ]);
    });
  });

  group('Reporters skipped files', () {
    const root = '/project';
    AnalysisResult resultWith(List<SkippedFile> skipped) => AnalysisResult(
      targetPath: root,
      duration: const Duration(milliseconds: 5),
      deadCodeReport: DeadCodeReport(
        unusedEntities: const [],
        totalDeclarations: 0,
        skippedFiles: skipped,
      ),
      complexityReport: ComplexityReport(
        files: const [],
        skippedFiles: skipped,
      ),
    );
    const skipped = [
      SkippedFile(
        filePath: '$root/lib/broken.dart',
        reason: '1 syntax error; first at line 1: Expected a type.',
      ),
    ];

    test('console reporter lists skipped files with reasons', () async {
      final output = await ConsoleReporter(
        useColors: false,
      ).generate(resultWith(skipped));

      expect(
        '⚠ Skipped 1 file that could not be analyzed:'.allMatches(output),
        hasLength(2),
        reason: 'once in the dead code and once in the complexity section',
      );
      expect(output, contains('  • lib/broken.dart\n'));
      expect(
        output,
        contains('    1 syntax error; first at line 1: Expected a type.\n'),
      );
    });

    test(
      'console reporter omits the section when nothing is skipped',
      () async {
        final output = await ConsoleReporter(
          useColors: false,
        ).generate(resultWith(const []));

        expect(output, isNot(contains('Skipped')));
      },
    );

    test('json reporter adds skippedFiles to each section', () async {
      final json =
          jsonDecode(await JsonReporter().generate(resultWith(skipped)))
              as Map<String, dynamic>;

      for (final section in ['deadCode', 'complexity']) {
        final report = json[section] as Map<String, dynamic>;
        expect(report['skippedFiles'], [
          {
            'filePath': 'lib/broken.dart',
            'reason': '1 syntax error; first at line 1: Expected a type.',
          },
        ]);
        expect(report['summary'], isA<Map>());
      }
      final deadCode = json['deadCode'] as Map<String, dynamic>;
      expect(deadCode['unusedEntities'], isEmpty);
      expect(json['complexity'] as Map, contains('files'));
    });

    test('SARIF reports skipped files as execution warnings', () async {
      final json =
          jsonDecode(await SarifReporter().generate(resultWith(skipped)))
              as Map;
      final invocation =
          ((json['runs'] as List).single['invocations'] as List).single;
      expect(invocation['executionSuccessful'], isFalse);
      for (final notification in invocation['toolExecutionNotifications']) {
        expect(notification['level'], 'warning');
        expect(notification['message']['text'], skipped.single.reason);
        expect(
          notification['locations'][0]['physicalLocation']['artifactLocation']['uri'],
          'lib/broken.dart',
        );
      }
      expect(invocation['toolExecutionNotifications'], hasLength(1));
      final workspace = AnalysisResult(
        targetPath: root,
        duration: Duration.zero,
        packageResults: [resultWith(skipped)],
      );
      expect(workspace.allFilesSkipped, isTrue);
    });

    test('SARIF marks a run without skips successful', () async {
      final json =
          jsonDecode(await SarifReporter().generate(resultWith(const [])))
              as Map;
      final invocation =
          ((json['runs'] as List).single['invocations'] as List).single;
      expect(invocation['executionSuccessful'], isTrue);
      expect(invocation['toolExecutionNotifications'], isEmpty);
    });

    test('json reporter emits an empty list when nothing is skipped', () async {
      final json =
          jsonDecode(await JsonReporter().generate(resultWith(const [])))
              as Map<String, dynamic>;

      expect((json['deadCode'] as Map)['skippedFiles'], isEmpty);
      expect((json['complexity'] as Map)['skippedFiles'], isEmpty);
    });
  });

  group('CLI skipped files', () {
    Future<void> expectSkippedFileWarning() async {
      final root = await _createPackage({'broken.dart': 'void broken( {'});

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        p.join(Directory.current.path, 'bin', 'hyena_dart.dart'),
        'analyze',
        root,
        '--format=json',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stderrText = result.stderr as String;
      expect(
        'Warning: skipped lib/broken.dart:'.allMatches(stderrText),
        hasLength(1),
        reason: 'one warning per file even when both analyzers skip it',
      );
      final json = jsonDecode(result.stdout as String) as Map;
      expect((json['deadCode'] as Map)['skippedFiles'], hasLength(1));
      expect((json['complexity'] as Map)['skippedFiles'], hasLength(1));
    }

    test(
      'warns on stderr and still writes a full report',
      expectSkippedFileWarning,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
