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
      expect(config.ignoreExports, false);
    });

    test('copyWith preserves values', () {
      final config = AnalyzerConfig(
        cyclomaticThreshold: 15,
        entryPoints: const ['AppRoutes'],
        entryPointAnnotations: const ['RoutePage'],
      );
      final copied = config.copyWith(maxNestingLevel: 3);
      expect(copied.cyclomaticThreshold, 15);
      expect(copied.maxNestingLevel, 3);
      expect(copied.entryPoints, ['AppRoutes']);
      expect(copied.entryPointAnnotations, ['RoutePage']);
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

    test('loads and validates configured dead-code entry points', () async {
      final fixture = await Directory.systemTemp.createTemp('hyena_config_');
      addTearDown(() => fixture.delete(recursive: true));
      final configPath = p.join(fixture.path, 'hyena.yaml');
      final configFile = File(configPath)
        ..writeAsStringSync('''
hyena:
  dead_code:
    entry_points:
      - AppRoutes
      - ServiceRegistry.register
    entry_point_annotations:
      - RoutePage
      - "@injectable"
      - riverpod.Riverpod
''');

      final config = await AnalyzerConfig.load(configPath);

      expect(config.entryPoints, ['AppRoutes', 'ServiceRegistry.register']);
      expect(config.entryPointAnnotations, [
        'RoutePage',
        'injectable',
        'riverpod.Riverpod',
      ]);

      configFile.writeAsStringSync('''
hyena:
  dead_code:
    entry_points: AppRoutes
''');
      await expectLater(
        AnalyzerConfig.load(configPath),
        throwsA(isA<FormatException>()),
      );
      configFile.writeAsStringSync('''
hyena:
  dead_code:
    entry_point_annotations: [RoutePage, 7]
''');
      await expectLater(
        AnalyzerConfig.load(configPath),
        throwsA(isA<FormatException>()),
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
        final file = File(p.join(lib.path, entry.key));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
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
      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
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
      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
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
      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final names = report.unusedEntities.map((e) => e.fullName).toSet();
      expect(names, contains('Holder.unusedGetter'));
      expect(names, contains('Holder.unusedSetter'));
      expect(names, isNot(contains('Holder.used')));
    });

    test(
      'keeps inherited implementations without override annotations',
      () async {
        final libPath = await makeFixture('''
abstract interface class Contract {
  void call();
  int get value;
  set value(int value);
}

class Implementation implements Contract {
  void call() {}
  int get value => 0;
  set value(int value) {}
}

void invoke(Contract contract) {
  contract.call();
  contract.value = contract.value + 1;
}

void main() => invoke(Implementation());
''');

        final report = await DeadCodeAnalyzer(
          AnalyzerConfig(ignoreExports: false),
        ).analyze(libPath);
        final unusedNames = report.unusedEntities
            .map((entity) => entity.fullName)
            .toSet();

        expect(unusedNames, isNot(contains('Implementation.call')));
        expect(unusedNames, isNot(contains('Implementation.value')));
      },
    );

    test('keeps overriding fields and their initializers reachable', () async {
      final libPath = await makeFixture('''
abstract interface class Contract {
  String get name;
  String get description;
}

String _buildName() => 'implementation';
String _buildDescription() => 'description';

class Implementation implements Contract {
  final String name = _buildName(), description = _buildDescription();
}

void main() {
  final Contract value = Implementation();
  print(value);
}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('Implementation.name')));
      expect(unusedNames, isNot(contains('Implementation.description')));
      expect(unusedNames, isNot(contains('_buildName')));
      expect(unusedNames, isNot(contains('_buildDescription')));
    });

    test('keeps members invoked through dynamic targets reachable', () async {
      final libPath = await makeFixture('''
void _dynamicHelper() {}

class DynamicTarget {
  void dynamicCall() => _dynamicHelper();
}

void main() {
  dynamic target = DynamicTarget();
  target.dynamicCall();
}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('DynamicTarget.dynamicCall')));
      expect(unusedNames, isNot(contains('_dynamicHelper')));
    });

    test('reports unused explicit constructors', () async {
      final libPath = await makeFixture('''
class Example {
  Example();
  Example.used();
  Example.unused();
  Example._private();
}

void main() => Example.used();
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final constructors = report.unusedEntities
          .where((entity) => entity.type == EntityType.constructor)
          .map((entity) => entity.fullName)
          .toSet();

      expect(
        constructors,
        containsAll(['Example.new', 'Example.unused', 'Example._private']),
      );
      expect(constructors, isNot(contains('Example.used')));
    });

    test('normalizes dot and trailing-separator target paths', () async {
      final libPath = await makeFixture('''
void unused() {}
void main() {}
''');
      final rootPath = p.dirname(libPath);
      final targets = [
        '$rootPath${p.separator}.',
        '$rootPath${p.separator}',
        '${p.join(rootPath, 'lib')}${p.separator}..',
      ];

      for (final target in targets) {
        final report = await DeadCodeAnalyzer(
          AnalyzerConfig(ignoreExports: false),
        ).analyze(target);
        expect(
          report.unusedEntities.map((entity) => entity.name),
          contains('unused'),
          reason: 'target $target should be canonicalized before analysis',
        );
      }
    });

    test(
      'CLI respects context boundaries for current-directory targets',
      () async {
        final libPath = await makeFixture('''
void unused() {}
void main() {}
''');
        final flutterSdkSource = File(
          p.join(
            p.dirname(libPath),
            '.fvm',
            'flutter_sdk',
            'packages',
            'flutter',
            'test_fixes',
            'services',
            'services.dart',
          ),
        );
        flutterSdkSource.parent.createSync(recursive: true);
        flutterSdkSource.writeAsStringSync('''
void applyFix() {
  await Future<void>.value();
}
''');
        final executable = p.normalize(p.absolute('bin', 'hyena_dart.dart'));

        final result = await Process.run(Platform.resolvedExecutable, [
          executable,
          'analyze',
          '.',
          '--format=json',
        ], workingDirectory: p.dirname(libPath));

        expect(result.exitCode, 0, reason: result.stderr as String);
        final report = jsonDecode(result.stdout as String) as Map;
        expect(report['targetPath'], '.');
        expect(
          (report['complexity'] as Map)['summary'],
          containsPair('totalFiles', 1),
        );
      },
    );

    test('honors dead-code suppression without cascading findings', () async {
      final libPath = await makeFixture('''
void _intentionalDependency() {}

// hyena:ignore dead-code
void intentionallyUnused() => _intentionalDependency();

void accidentallyUnused() {}
void main() {}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, contains('accidentallyUnused'));
      expect(unusedNames, isNot(contains('intentionallyUnused')));
      expect(unusedNames, isNot(contains('_intentionalDependency')));
    });

    test('keeps configured framework entry points and dependencies', () async {
      final libPath = await makeFixture('''
void _routeDependency() {}
void _serviceDependency() {}
void _callbackDependency() {}
void _serializerDependency() {}

class AppRoutes {
  static void configure() => _routeDependency();
  static void generatedRoute() {}
}

class ServiceRegistry {
  static void register() => _serviceDependency();
  static void accidentalMethod() {}
}

class OtherRegistry {
  static void register() {}
}

class JsonAdapter {
  static Map<String, Object?> fromJson(Map<String, Object?> json) {
    _serializerDependency();
    return json;
  }

  static void unusedAdapter() {}
}

final callbacks = <void Function()>[_registeredCallback];
void _registeredCallback() => _callbackDependency();
typedef _Serializer = Map<String, Object?> Function(Map<String, Object?>);

void unrelatedFunction() {}
void main() {}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(
          ignoreExports: false,
          entryPoints: const [
            'AppRoutes',
            'ServiceRegistry.register',
            'JsonAdapter.fromJson',
            'callbacks',
            '_Serializer',
          ],
        ),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(
        unusedNames.intersection({
          'AppRoutes',
          'AppRoutes.configure',
          'AppRoutes.generatedRoute',
          '_routeDependency',
          'ServiceRegistry',
          'ServiceRegistry.register',
          '_serviceDependency',
          'JsonAdapter',
          'JsonAdapter.fromJson',
          '_serializerDependency',
          'callbacks',
          '_registeredCallback',
          '_callbackDependency',
          '_Serializer',
        }),
        isEmpty,
      );
      expect(
        unusedNames,
        containsAll([
          'ServiceRegistry.accidentalMethod',
          'OtherRegistry',
          'OtherRegistry.register',
          'JsonAdapter.unusedAdapter',
          'unrelatedFunction',
        ]),
      );
    });

    test('recognizes short and prefixed entry-point annotations', () async {
      final libPath = await makeFixture(
        '''
import 'annotations.dart' as framework;
import 'annotations.dart' as riverpod;

void _routeDependency() {}
void _serviceDependency() {}
void _providerDependency() {}
void _pluginDependency() {}

@framework.RoutePage()
class GeneratedRoute {
  void build() => _routeDependency();
  void generatedCallback() {}
}

@framework.injectable
void registerService() => _serviceDependency();

@riverpod.Riverpod()
int generatedProvider() {
  _providerDependency();
  return 0;
}

@framework.PluginEntry()
void registerPlugin() => _pluginDependency();

@framework.Riverpod()
void wrongPrefix() {}

void unrelatedFunction() {}
void main() {}
''',
        additionalFiles: {
          'annotations.dart': '''
class RoutePage {
  const RoutePage();
}

class Riverpod {
  const Riverpod();
}

class PluginEntry {
  const PluginEntry();
}

class Injectable {
  const Injectable();
}

const injectable = Injectable();
''',
        },
      );

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(
          ignoreExports: false,
          entryPointAnnotations: const [
            'RoutePage',
            '@injectable',
            'riverpod.Riverpod',
            'PluginEntry',
          ],
        ),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(
        unusedNames.intersection({
          'GeneratedRoute',
          'GeneratedRoute.build',
          'GeneratedRoute.generatedCallback',
          '_routeDependency',
          'registerService',
          '_serviceDependency',
          'generatedProvider',
          '_providerDependency',
          'registerPlugin',
          '_pluginDependency',
        }),
        isEmpty,
      );
      expect(unusedNames, containsAll(['wrongPrefix', 'unrelatedFunction']));
    });

    test(
      'applies annotations to constructors, fields, aliases, and enums',
      () async {
        final libPath = await makeFixture('''
class FrameworkEntry {
  const FrameworkEntry();
}

void _constructorDependency() {}
void _fieldDependency() {}
void _aliasDependency(FrameworkCallback callback) => callback();
void _enumDependency() {}

class FrameworkHooks {
  @FrameworkEntry()
  FrameworkHooks.generated() {
    _constructorDependency();
  }

  @FrameworkEntry()
  static final callback = _fieldDependency;

  static void unusedHook() {}
}

@FrameworkEntry()
typedef FrameworkCallback = void Function();

enum GeneratedMode {
  @FrameworkEntry()
  generated,
  unused;

  void run() => _enumDependency();
}

void unrelatedFunction() {}
void main() {}
''');

        final report = await DeadCodeAnalyzer(
          AnalyzerConfig(
            ignoreExports: false,
            entryPointAnnotations: const ['FrameworkEntry'],
          ),
        ).analyze(libPath);
        final unusedNames = report.unusedEntities
            .map((entity) => entity.fullName)
            .toSet();

        expect(
          unusedNames.intersection({
            'FrameworkHooks',
            'FrameworkHooks.generated',
            'FrameworkHooks.callback',
            '_constructorDependency',
            '_fieldDependency',
            'FrameworkCallback',
            'GeneratedMode',
            'GeneratedMode.generated',
          }),
          isEmpty,
        );
        expect(
          unusedNames,
          containsAll([
            'FrameworkHooks.unusedHook',
            'GeneratedMode.unused',
            'GeneratedMode.run',
            '_aliasDependency',
            '_enumDependency',
            'unrelatedFunction',
          ]),
        );
      },
    );

    test(
      'CLI applies entry points loaded from project configuration',
      () async {
        final libPath = await makeFixture('''
void _generatedDependency() {}
void generatedCallback() => _generatedDependency();
void unrelatedFunction() {}
void main() {}
''');
        File(p.join(p.dirname(libPath), 'hyena.yaml')).writeAsStringSync('''
hyena:
  dead_code:
    ignore_exports: false
    entry_points:
      - generatedCallback
''');
        final output = <String>[];

        await runZoned(
          () =>
              HyenaCommandRunner().run(['dead-code', libPath, '--format=json']),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, message) => output.add(message),
          ),
        );

        final json = jsonDecode(output.join('\n')) as Map<String, dynamic>;
        final deadCode = json['deadCode'] as Map<String, dynamic>;
        final entities = (deadCode['unusedEntities'] as List).cast<Map>();
        expect(entities.map((entity) => entity['name']), ['unrelatedFunction']);
      },
    );

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

    test(
      'analyze reports public APIs by default and can preserve them explicitly',
      () async {
        final libPath = await makeFixture('void unusedPublicApi() {}');
        final defaultOutput = <String>[];

        await runZoned(
          () => HyenaCommandRunner().run([
            'analyze',
            libPath,
            '--no-complexity',
            '--format=json',
          ]),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, message) => defaultOutput.add(message),
          ),
        );

        final defaultJson =
            jsonDecode(defaultOutput.join('\n')) as Map<String, dynamic>;
        final defaultDeadCode = defaultJson['deadCode'] as Map<String, dynamic>;
        final defaultEntities = (defaultDeadCode['unusedEntities'] as List)
            .cast<Map>();
        expect(
          defaultEntities.map((entity) => entity['name']),
          contains('unusedPublicApi'),
        );

        final output = <String>[];

        await runZoned(
          () => HyenaCommandRunner().run([
            'analyze',
            libPath,
            '--ignore-exports',
            '--no-complexity',
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
      },
    );

    test('reports one-based declaration lines and columns', () async {
      final libPath = await makeFixture('\n  void unusedFunction() {}\n');
      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(p.join(libPath, 'lib.dart'));

      final entity = report.unusedEntities.single;
      expect(entity.line, 2);
      expect(entity.column, 8);
    });

    test('does not flag declarations exported by a barrel file', () async {
      final libPath = await makeFixture(
        "export 'src/api.dart';",
        additionalFiles: {'src/api.dart': 'class PublicApi {}'},
      );

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);

      expect(
        report.unusedEntities.map((entity) => entity.name),
        isNot(contains('PublicApi')),
      );
    });

    test('respects show and hide export combinators', () async {
      final libPath = await makeFixture(
        "export 'src/api.dart' show VisibleApi, HiddenApi hide HiddenApi;",
        additionalFiles: {
          'src/api.dart': 'class VisibleApi {}\nclass HiddenApi {}',
        },
      );

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, isNot(contains('VisibleApi')));
      expect(unusedNames, contains('HiddenApi'));
    });

    test('treats directly importable libraries as public APIs', () async {
      final libPath = await makeFixture('''
void _helper() {}

class PublicApi {
  void call() => _helper();
  void _privateMethod() {}
}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('PublicApi')));
      expect(unusedNames, isNot(contains('PublicApi.call')));
      expect(unusedNames, isNot(contains('_helper')));
      expect(unusedNames, contains('PublicApi._privateMethod'));
    });

    test('includes part declarations in a public library API', () async {
      final libPath = await makeFixture(
        "part 'src/api_part.dart';",
        additionalFiles: {
          'src/api_part.dart': '''
part of '../lib.dart';

class PartApi {
  void call() {}
}
''',
        },
      );

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();

      expect(unusedNames, isNot(contains('PartApi')));
      expect(unusedNames, isNot(contains('PartApi.call')));
    });

    test(
      'includes part declarations from explicitly exported libraries',
      () async {
        final libPath = await makeFixture(
          "export 'src/api.dart';",
          additionalFiles: {
            'src/api.dart': "part 'api_part.dart';",
            'src/api_part.dart': '''
part of 'api.dart';

class ExportedPartApi {
  void call() {}
}
''',
          },
        );

        final report = await DeadCodeAnalyzer(
          AnalyzerConfig(ignoreExports: true),
        ).analyze(libPath);
        final unusedNames = report.unusedEntities
            .map((entity) => entity.fullName)
            .toSet();

        expect(unusedNames, isNot(contains('ExportedPartApi')));
        expect(unusedNames, isNot(contains('ExportedPartApi.call')));
      },
    );

    test('includes every branch of a conditional export', () async {
      final libPath = await makeFixture(
        "export 'src/default.dart' if (dart.library.io) 'src/io.dart';",
        additionalFiles: {
          'src/default.dart': 'class DefaultApi {}',
          'src/io.dart': 'class IoApi {}',
        },
      );

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, isNot(contains('DefaultApi')));
      expect(unusedNames, isNot(contains('IoApi')));
    });

    test('keeps every conditional import implementation reachable', () async {
      final libPath = await makeFixture(
        '''
import 'src/default.dart' if (dart.library.io) 'src/io.dart';

void main() => createImplementation();
''',
        additionalFiles: {
          'src/default.dart': '''
void createImplementation() => _defaultHelper();
void _defaultHelper() {}
''',
          'src/io.dart': '''
void createImplementation() => _ioHelper();
void _ioHelper() {}
''',
        },
      );

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(libPath);
      final unusedNames = report.unusedEntities
          .map((entity) => entity.name)
          .toSet();

      expect(unusedNames, isNot(contains('createImplementation')));
      expect(unusedNames, isNot(contains('_defaultHelper')));
      expect(unusedNames, isNot(contains('_ioHelper')));
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

    test('skips files outside the analyzer context', () async {
      final libPath = await makeFixture('''
void unused() {}
void main() {}
''');
      final root = p.dirname(libPath);
      for (final relativePath in [
        p.join('.dart_tool', 'generated', 'invalid.dart'),
        p.join('build', 'invalid.dart'),
        p.join('.delta', 'worktrees', 'nested', 'lib', 'auth_api.dart'),
        p.join('.another_tool', 'worktrees', 'invalid.dart'),
      ]) {
        final file = File(p.join(root, relativePath));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('void broken( {');
      }

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(root);

      expect(report.unusedEntities.map((entity) => entity.name), ['unused']);
    });

    test('analyzes an explicitly targeted tool-named directory', () async {
      final container = await Directory.systemTemp.createTemp(
        'hyena_explicit_target_',
      );
      created.add(container);
      final target = Directory(
        p.join(container.path, '.delta', 'worktrees', 'project'),
      )..createSync(recursive: true);
      File(p.join(target.path, 'source.dart')).writeAsStringSync('''
void unused() {}
void main() {}
''');

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: false),
      ).analyze(target.path);

      expect(report.unusedEntities.map((entity) => entity.name), ['unused']);
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

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);
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

      final report = await DeadCodeAnalyzer(
        AnalyzerConfig(ignoreExports: true),
      ).analyze(libPath);
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
      final source = File(p.join(fixture.path, 'sample.dart'))
        ..writeAsStringSync('''

void target() {}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(source.path);

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

    test('honors broad and rule-specific complexity suppressions', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''
// hyena:ignore complexity
void suppressedAll(int value) {
  if (value > 0) print(value);
}

// hyena:ignore cyclomatic-complexity
void suppressedCyclomatic() {
  if (true) print('value');
}

// hyena:ignore max-nesting
void suppressedNesting() {
  if (true) print('value');
}

// hyena:ignore max-parameters
void suppressedParameters(int value) {}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(
          cyclomaticThreshold: 1,
          maxNestingLevel: 0,
          maxParameters: 0,
        ),
      ).analyze(fixture.path);

      expect(
        report.highComplexityFunctions.map((metrics) => metrics.name),
        contains('suppressedNesting'),
      );
      expect(
        report.highComplexityFunctions.map((metrics) => metrics.name),
        isNot(contains('suppressedAll')),
      );
      expect(
        report.highComplexityFunctions.map((metrics) => metrics.name),
        isNot(contains('suppressedCyclomatic')),
      );
      expect(
        report.highNestingFunctions.map((metrics) => metrics.name),
        contains('suppressedCyclomatic'),
      );
      expect(
        report.highNestingFunctions.map((metrics) => metrics.name),
        isNot(contains('suppressedNesting')),
      );
      expect(
        report.highParameterFunctions.map((metrics) => metrics.name),
        isNot(contains('suppressedParameters')),
      );
      expect(
        report.thresholdViolations.map((metrics) => metrics.name),
        isNot(contains('suppressedAll')),
      );
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

    test('includes constructor initializers in constructor metrics', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''
class Base {
  Base(int input);
}

class Example extends Base {
  final int value;

  Example(bool enabled, int input)
      : assert(enabled),
        value = enabled ? input : 0,
        super(enabled ? input : 1) {
    print(value);
  }

  Example.redirect(bool enabled, int input) : this(enabled, input);
}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);
      final functions = report.files.single.functions;
      final constructor = functions.singleWhere(
        (function) => function.fullName == 'Example.new',
      );
      final redirectingConstructor = functions.singleWhere(
        (function) => function.fullName == 'Example.redirect',
      );

      expect(constructor.cyclomaticComplexity, 4);
      expect(constructor.linesOfCode, 5);
      expect(constructor.halsteadVolume, greaterThan(0));
      expect(redirectingConstructor.cyclomaticComplexity, 1);
      expect(redirectingConstructor.linesOfCode, 1);
      expect(redirectingConstructor.halsteadVolume, greaterThan(0));
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

    test('accepts non-error parser diagnostics', () async {
      File(p.join(fixture.path, 'sample.dart')).writeAsStringSync('''
/// {@example /example/lib/sample.dart#body}
void documented() {}
''');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);

      expect(report.totalFunctions, 1);
    });

    test('skips files outside the analyzer context', () async {
      File(
        p.join(fixture.path, 'sample.dart'),
      ).writeAsStringSync('void target() {}');
      for (final relativePath in [
        p.join('.dart_tool', 'generated', 'invalid.dart'),
        p.join('build', 'invalid.dart'),
        p.join(
          '.fvm',
          'flutter_sdk',
          'packages',
          'flutter',
          'test_fixes',
          'services',
          'services.dart',
        ),
        p.join('.another_tool', 'worktrees', 'invalid.dart'),
      ]) {
        final file = File(p.join(fixture.path, relativePath));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('void broken( {');
      }

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(fixture.path);

      expect(report.totalFiles, 1);
      expect(report.totalFunctions, 1);
    });

    test('analyzes an explicitly targeted tool-named directory', () async {
      final target = Directory(
        p.join(fixture.path, '.fvm', 'flutter_sdk', 'project'),
      )..createSync(recursive: true);
      File(
        p.join(target.path, 'source.dart'),
      ).writeAsStringSync('void target() {}');

      final report = await ComplexityAnalyzer(
        AnalyzerConfig(),
      ).analyze(target.path);

      expect(report.totalFiles, 1);
      expect(report.totalFunctions, 1);
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

  test('MarkdownReporter escapes source-controlled markup', () async {
    const payload = '</summary>![private](https://example.invalid/track)|';
    final report = DeadCodeReport(
      unusedEntities: [
        CodeEntity(
          name: payload,
          type: EntityType.function,
          filePath: payload,
          line: 1,
          column: 1,
          isPublic: true,
        ),
      ],
      totalDeclarations: 1,
    );

    final markdown = await MarkdownReporter().generate(
      AnalysisResult(
        deadCodeReport: report,
        targetPath: payload,
        duration: Duration.zero,
      ),
    );

    expect(markdown, isNot(contains(payload)));
    expect(markdown, isNot(contains('![private]')));
    expect(markdown, contains('&lt;/summary&gt;'));
    expect(markdown, contains('&#33;&#91;private&#93;'));
    expect(markdown, contains('&#124;'));
  });
}
