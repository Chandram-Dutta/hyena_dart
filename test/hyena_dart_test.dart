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
    final created = <Directory>[];

    Future<String> makeFixture(String libSource) async {
      final fixture = await Directory.systemTemp.createTemp('hyena_fixture_');
      created.add(fixture);
      final lib = Directory(p.join(fixture.path, 'lib'))..createSync();
      File(p.join(fixture.path, 'pubspec.yaml')).writeAsStringSync('''
name: hyena_fixture
environment:
  sdk: ^3.10.0
''');
      File(p.join(lib.path, 'lib.dart')).writeAsStringSync(libSource);
      final result = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: fixture.path);
      if (result.exitCode != 0) {
        throw StateError('pub get failed: ${result.stderr}');
      }
      return p.join(fixture.path, 'lib');
    }

    tearDownAll(() async {
      for (final dir in created) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('detects same-named method on unused class', () async {
      final libPath = await makeFixture('''
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
      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);
      final names = report.unusedEntities.map((e) => e.fullName).toSet();
      expect(names, contains('ShouldBeDead'));
      expect(names, contains('ShouldBeDead.hello'));
      expect(names, isNot(contains('Used')));
      expect(names, isNot(contains('Used.hello')));
    });

    test('distinguishes same-named fields across classes', () async {
      final libPath = await makeFixture('''
class Foo {
  int counter = 0;
}

class Bar {
  int counter = 0;
  void inc() { counter++; }
}

void main() {
  final b = Bar();
  b.inc();
}
''');
      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);
      final names = report.unusedEntities.map((e) => e.fullName).toSet();
      expect(names, contains('Foo.counter'));
      expect(names, isNot(contains('Bar.counter')));
    });

    test('flags unused getter and setter, keeps used ones', () async {
      final libPath = await makeFixture('''
class Holder {
  int _value = 0;

  int get used => _value;
  set used(int v) => _value = v;

  int get unusedGetter => 0;
  set unusedSetter(int v) {}
}

void main() {
  final h = Holder();
  h.used = 5;
  print(h.used);
}
''');
      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);
      final names = report.unusedEntities.map((e) => e.fullName).toSet();
      expect(names, contains('Holder.unusedGetter'));
      expect(names, contains('Holder.unusedSetter'));
      expect(names, isNot(contains('Holder.used')));
    });
  });
}
