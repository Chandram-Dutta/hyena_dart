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
        totalDeclarations: 3,
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
