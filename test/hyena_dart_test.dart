import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AnalyzerConfig', () {
    test('creates default config', () {
      final config = AnalyzerConfig();
      expect(config.cyclomaticThreshold, 20);
      expect(config.maxNestingLevel, 5);
      expect(config.ignoreExports, true);
    });

    test('copyWith preserves values', () {
      final config = AnalyzerConfig(cyclomaticThreshold: 15);
      final copied = config.copyWith(maxNestingLevel: 3);
      expect(copied.cyclomaticThreshold, 15);
      expect(copied.maxNestingLevel, 3);
    });
  });

  group('CodeEntity', () {
    test('fullName includes parent', () {
      final entity = CodeEntity(
        name: 'method',
        type: EntityType.method,
        filePath: 'test.dart',
        line: 1,
        column: 0,
        parentName: 'MyClass',
        isPublic: true,
      );
      expect(entity.fullName, 'MyClass.method');
    });

    test('typeLabel returns correct label', () {
      final entity = CodeEntity(
        name: 'MyClass',
        type: EntityType.classDecl,
        filePath: 'test.dart',
        line: 1,
        column: 0,
        isPublic: true,
      );
      expect(entity.typeLabel, 'class');
    });
  });

  group('DeadCodeAnalyzer (resolved AST)', () {
    late Directory fixture;

    setUpAll(() async {
      fixture = await Directory.systemTemp.createTemp('hyena_fixture_');
      final lib = Directory(p.join(fixture.path, 'lib'))..createSync();
      File(p.join(fixture.path, 'pubspec.yaml')).writeAsStringSync('''
name: hyena_fixture
environment:
  sdk: ^3.10.0
''');
      File(p.join(lib.path, 'lib.dart')).writeAsStringSync('''
class Used {
  void hello() => print('used');
}

class ShouldBeDead {
  void hello() => print('dead');
}

void main() {
  final u = Used();
  u.hello();
}
''');
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['pub', 'get'],
        workingDirectory: fixture.path,
      );
      if (result.exitCode != 0) {
        throw StateError('pub get failed: ${result.stderr}');
      }
    });

    tearDownAll(() async {
      if (await fixture.exists()) {
        await fixture.delete(recursive: true);
      }
    });

    test('detects same-named method on unused class', () async {
      final analyzer = DeadCodeAnalyzer(AnalyzerConfig());
      final report = await analyzer.analyze(p.join(fixture.path, 'lib'));
      final names = report.unusedEntities.map((e) => e.fullName).toSet();
      expect(names, contains('ShouldBeDead'));
      expect(names, contains('ShouldBeDead.hello'));
      expect(names, isNot(contains('Used')));
      expect(names, isNot(contains('Used.hello')));
    });
  });
}
