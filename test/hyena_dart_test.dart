import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

    test('discovers configuration from the target project', () async {
      final fixture = await Directory.systemTemp.createTemp('hyena_config_');
      addTearDown(() => fixture.delete(recursive: true));
      final lib = Directory(p.join(fixture.path, 'lib'))..createSync();
      File(p.join(fixture.path, 'hyena.yaml')).writeAsStringSync('''
hyena:
  complexity:
    cyclomatic_threshold: 7
''');

      final config = await AnalyzerConfig.load(null, targetPath: lib.path);

      expect(config.cyclomaticThreshold, 7);
    });

    test('rejects malformed and missing explicit configuration', () async {
      final fixture = await Directory.systemTemp.createTemp('hyena_config_');
      addTearDown(() => fixture.delete(recursive: true));
      final invalidPath = p.join(fixture.path, 'invalid.yaml');
      File(invalidPath).writeAsStringSync('hyena: [not valid for this schema]');

      await expectLater(
        AnalyzerConfig.load(invalidPath),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        AnalyzerConfig.load(p.join(fixture.path, 'missing.yaml')),
        throwsA(isA<ArgumentError>()),
      );
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

    Future<String> makeFixture(
      String libSource, {
      Map<String, String> additionalFiles = const {},
    }) async {
      final fixture = await Directory.systemTemp.createTemp('hyena_fixture_');
      created.add(fixture);
      final lib = Directory(p.join(fixture.path, 'lib'))..createSync();
      File(p.join(fixture.path, 'pubspec.yaml')).writeAsStringSync('''
name: hyena_fixture
environment:
  sdk: ^3.10.0
''');
      File(p.join(lib.path, 'lib.dart')).writeAsStringSync(libSource);
      for (final entry in additionalFiles.entries) {
        File(p.join(lib.path, entry.key)).writeAsStringSync(entry.value);
      }
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

    test('honors ignoreMain when it is disabled', () async {
      final libPath = await makeFixture('void main() {}');
      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreMain: false, ignoreExports: false),
      ).analyze(libPath);

      expect(report.totalDeclarations, 1);
      expect(report.unusedEntities, isEmpty);
    });

    test('CLI defaults do not overwrite YAML dead-code settings', () async {
      final libPath = await makeFixture('void _unusedPrivate() {}');
      final configPath = p.join(p.dirname(libPath), 'hyena.yaml');
      File(configPath).writeAsStringSync('''
hyena:
  dead_code:
    ignore_private: true
''');
      final output = <String>[];

      await runZoned(
        () => HyenaCommandRunner().run([
          'dead-code',
          libPath,
          '--config=$configPath',
          '--format=json',
        ]),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, message) => output.add(message),
        ),
      );

      final json = jsonDecode(output.join('\n')) as Map<String, dynamic>;
      final deadCode = json['deadCode'] as Map<String, dynamic>;
      final summary = deadCode['summary'] as Map<String, dynamic>;
      expect(summary['unusedCount'], 0);
    });

    test('CLI discovers configuration beside the target package', () async {
      final libPath = await makeFixture('void _unusedPrivate() {}');
      File(p.join(p.dirname(libPath), 'hyena.yaml')).writeAsStringSync('''
hyena:
  dead_code:
    ignore_private: true
''');
      final output = <String>[];

      await runZoned(
        () => HyenaCommandRunner().run(['dead-code', libPath, '--format=json']),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, message) => output.add(message),
        ),
      );

      final json = jsonDecode(output.join('\n')) as Map<String, dynamic>;
      final deadCode = json['deadCode'] as Map<String, dynamic>;
      final summary = deadCode['summary'] as Map<String, dynamic>;
      expect(summary['unusedCount'], 0);
    });

    test('reports one-based declaration lines and columns', () async {
      final libPath = await makeFixture('\n  void unusedFunction() {}\n');
      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);

      final entity = report.unusedEntities.single;
      expect(entity.line, 2);
      expect(entity.column, 8);
    });

    test('does not flag declarations exported by a barrel file', () async {
      final libPath = await makeFixture(
        "export 'api.dart';",
        additionalFiles: {'api.dart': 'class PublicApi {}'},
      );

      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);

      expect(
        report.unusedEntities.map((entity) => entity.name),
        isNot(contains('PublicApi')),
      );
    });

    test('respects show and hide export combinators', () async {
      final libPath = await makeFixture(
        "export 'api.dart' show VisibleApi, HiddenApi hide HiddenApi;",
        additionalFiles: {
          'api.dart': 'class VisibleApi {}\nclass HiddenApi {}',
        },
      );

      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, isNot(contains('VisibleApi')));
      expect(unusedNames, contains('HiddenApi'));
    });

    test('keeps an extension alive when one of its members is used', () async {
      final libPath = await makeFixture('''
extension UsefulExtension on String {
  int get doubledLength => length * 2;
}

void main() {
  print('hi'.doubledLength);
}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('UsefulExtension')));
      expect(unusedNames, isNot(contains('UsefulExtension.doubledLength')));
    });

    test('detects and tracks extension types', () async {
      final libPath = await makeFixture('''
extension type UserId(int value) {
  bool get isValid => value > 0;
}

void main() {
  print(UserId(1).isValid);
}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('UserId')));
      expect(unusedNames, isNot(contains('UserId.isValid')));
      expect(
        report.totalDeclarations,
        greaterThanOrEqualTo(2),
        reason: 'the extension type and its getter should both be collected',
      );
    });

    test('fails instead of silently skipping unresolved source', () async {
      final libPath = await makeFixture('void broken( {');

      await expectLater(
        DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('lib.dart'),
          ),
        ),
      );
    });

    test('reports declarations reachable only from dead code', () async {
      final libPath = await makeFixture('''
void firstDeadFunction() => secondDeadFunction();
void secondDeadFunction() {}

void main() {}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(
        unusedNames,
        containsAll(['firstDeadFunction', 'secondDeadFunction']),
      );
    });

    test('keeps transitively reachable declarations alive', () async {
      final libPath = await makeFixture('''
void firstLiveFunction() => secondLiveFunction();
void secondLiveFunction() {}

void main() {
  firstLiveFunction();
}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, isNot(contains('firstLiveFunction')));
      expect(unusedNames, isNot(contains('secondLiveFunction')));
    });

    test('treats exported APIs as reachability roots', () async {
      final libPath = await makeFixture(
        "export 'api.dart';",
        additionalFiles: {
          'api.dart': '''
void publicApi() => _implementation();
void _implementation() {}
''',
        },
      );

      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, isNot(contains('publicApi')));
      expect(unusedNames, isNot(contains('_implementation')));
    });

    test('treats public members of exported types as API roots', () async {
      final libPath = await makeFixture(
        "export 'api.dart';",
        additionalFiles: {
          'api.dart': '''
void _methodHelper() {}
void _constructorHelper() {}

class Api {
  Api() {
    _constructorHelper();
  }

  void call() => _methodHelper();
  void _privateMethod() {}
}

extension ApiExtension on String {
  void callExtension() => _methodHelper();
  void _privateExtensionMethod() {}
}
''',
        },
      );

      final report = await DeadCodeAnalyzer(AnalyzerConfig()).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('Api.call')));
      expect(unusedNames, isNot(contains('ApiExtension.callExtension')));
      expect(unusedNames, isNot(contains('_methodHelper')));
      expect(unusedNames, isNot(contains('_constructorHelper')));
      expect(unusedNames, contains('Api._privateMethod'));
      expect(unusedNames, contains('ApiExtension._privateExtensionMethod'));
    });
  });

  group('ComplexityAnalyzer source locations', () {
    late Directory fixture;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('hyena_complexity_');
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('reports function lines instead of offsets', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''

void target() {}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);

      expect(report.files.single.functions.single.line, 2);
    });

    test('does not count a trailing newline as a blank line', () async {
      File(
        p.join(fixture.path, 'sample.dart'),
      ).writeAsStringSync('void target() {}\n');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);
      final metrics = report.files.single;

      expect(metrics.totalLines, 1);
      expect(metrics.codeLines, 1);
      expect(metrics.blankLines, 0);
    });

    test('analyzes constructors and closures in their own scopes', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''
class Example {
  Example(bool enabled) {
    if (enabled) print('enabled');
  }
}

final callback = (bool enabled) {
  if (enabled) print('callback');
};

void outer() {
  final nested = (bool enabled) {
    if (enabled) print('nested');
  };
  print(nested);
}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);
      final functions = report.files.single.functions;
      final constructor = functions.singleWhere(
        (function) => function.fullName == 'Example.new',
      );
      final outer = functions.singleWhere(
        (function) => function.fullName == 'outer',
      );
      final closures = functions.where(
        (function) => function.name.startsWith('<closure@'),
      );

      expect(constructor.cyclomaticComplexity, 2);
      expect(outer.cyclomaticComplexity, 1);
      expect(closures, hasLength(2));
      expect(
        closures.map((function) => function.cyclomaticComplexity),
        everyElement(2),
      );
      expect(
        functions.map((function) => function.halsteadVolume),
        everyElement(greaterThan(0)),
      );
    });

    test('excludes nested closure bodies from outer metrics', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''
void withSmallClosure() {
  final nested = () {
    print('small');
  };
  print(nested);
}

void withLargeClosure() {
  final nested = () {
    var value = 0;
    value++;
    value *= 2;
    print(value);
  };
  print(nested);
}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);
      final functions = report.files.single.functions;
      final smallOuter = functions.singleWhere(
        (function) => function.name == 'withSmallClosure',
      );
      final largeOuter = functions.singleWhere(
        (function) => function.name == 'withLargeClosure',
      );
      final closures = functions
          .where((function) => function.name.startsWith('<closure@'))
          .toList();

      expect(largeOuter.linesOfCode, smallOuter.linesOfCode);
      expect(largeOuter.halsteadVolume, smallOuter.halsteadVolume);
      expect(closures, hasLength(2));
      expect(
        closures.last.linesOfCode,
        greaterThan(closures.first.linesOfCode),
      );
      expect(
        closures.last.halsteadVolume,
        greaterThan(closures.first.halsteadVolume),
      );
    });

    test('counts for-in loops once', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''
void iterate(List<int> values) {
  for (final value in values) {
    print(value);
  }
}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);

      expect(report.files.single.functions.single.cyclomaticComplexity, 2);
    });

    test('fails instead of silently omitting invalid files', () async {
      final source = File(p.join(fixture.path, 'broken.dart'))
        ..writeAsStringSync('void broken( {');

      await expectLater(
        ComplexityAnalyzer(AnalyzerConfig()).analyze(fixture.path),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(source.path),
          ),
        ),
      );
    });
  });

  group('ComplexityReport thresholds', () {
    FunctionMetrics metrics({
      required String name,
      int cyclomatic = 1,
      int nesting = 0,
      int parameters = 0,
    }) => FunctionMetrics(
      name: name,
      filePath: 'test.dart',
      line: 1,
      cyclomaticComplexity: cyclomatic,
      linesOfCode: 1,
      maxNestingLevel: nesting,
      parameterCount: parameters,
    );

    test('applies cyclomatic, nesting, and parameter thresholds', () {
      final report = ComplexityReport(
        files: [
          FileMetrics(
            filePath: 'test.dart',
            totalLines: 4,
            codeLines: 4,
            commentLines: 0,
            blankLines: 0,
            functions: [
              metrics(name: 'complex', cyclomatic: 4),
              metrics(name: 'nested', nesting: 3),
              metrics(name: 'wide', parameters: 3),
              metrics(name: 'fine'),
            ],
          ),
        ],
        cyclomaticThreshold: 3,
        maxNestingLevel: 2,
        maxParameters: 2,
      );

      expect(report.highComplexityFunctions.single.name, 'complex');
      expect(report.highNestingFunctions.single.name, 'nested');
      expect(report.highParameterFunctions.single.name, 'wide');
      expect(
        report.thresholdViolations.map((function) => function.name),
        containsAll(['complex', 'nested', 'wide']),
      );
      expect(report.thresholdViolations, hasLength(3));
    });

    test('uses measured Halstead volume in the normalized index', () {
      final metrics = FunctionMetrics(
        name: 'measured',
        filePath: 'test.dart',
        line: 1,
        cyclomaticComplexity: 2,
        linesOfCode: 10,
        maxNestingLevel: 1,
        parameterCount: 1,
        halsteadVolume: 100,
      );
      final expected =
          (171 - 5.2 * math.log(100) - 0.23 * 2 - 16.2 * math.log(10)) *
          100 /
          171;

      expect(metrics.maintainabilityIndex, closeTo(expected, 0.000001));
    });
  });

  test('HtmlReporter escapes source-controlled text', () async {
    final report = DeadCodeReport(
      unusedEntities: [
        CodeEntity(
          name: '<script>alert(1)</script>',
          type: EntityType.function,
          filePath: '<img src=x onerror=alert(1)>',
          line: 1,
          column: 1,
          isPublic: true,
        ),
      ],
      totalDeclarations: 1,
    );

    final html = await HtmlReporter().generate(
      AnalysisResult(
        deadCodeReport: report,
        targetPath: '<script>target</script>',
        duration: Duration.zero,
      ),
    );

    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(html, isNot(contains('<img src=x onerror=alert(1)>')));
    expect(html, contains('&lt;script&gt;target&lt;&#47;script&gt;'));
    expect(html, contains('&lt;img src=x onerror=alert(1)&gt;'));
  });
}
