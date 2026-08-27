import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../benchmark/src/corpus.dart';
import '../benchmark/src/harness.dart';

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('hyena_benchmark_test_');
  });

  tearDown(() async {
    await scratch.delete(recursive: true);
  });

  test(
    'single-package corpus is deterministic and exercises both checks',
    () async {
      final corpus = await BenchmarkCorpusGenerator(
        scratch,
      ).singlePackage(id: 'single_test', fileCount: 3);

      expect(corpus.dartFiles, 4);
      expect(corpus.packageCount, 1);
      final result = await const AnalysisRunner().analyze(corpus.targetPath);
      expect(result.deadCodeReport!.totalDeclarations, 24);
      expect(result.deadCodeReport!.unusedCount, 12);
      expect(result.complexityReport!.totalFiles, corpus.dartFiles);
      expect(result.complexityReport!.totalFunctions, 19);
    },
  );

  test(
    'workspace corpus resolves cross-package references without pub get',
    () async {
      final corpus = await BenchmarkCorpusGenerator(
        scratch,
      ).workspace(id: 'workspace_test', packages: 2, filesPerPackage: 2);

      expect(corpus.dartFiles, 5);
      expect(corpus.packageCount, 3);
      final result = await const AnalysisRunner().analyze(corpus.targetPath);
      expect(result.packageAnalyses.length, corpus.packageCount);
      expect(
        result.packageAnalyses.fold<int>(
          0,
          (sum, package) => sum + package.complexityReport!.totalFiles,
        ),
        corpus.dartFiles,
      );

      final designSystem = result.packageAnalyses.singleWhere(
        (package) => package.packageName == 'design_system',
      );
      final unused = designSystem.deadCodeReport!.unusedEntities
          .map((entity) => entity.fullName)
          .toSet();
      expect(unused, isNot(contains('liveP01F0000')));
      expect(unused, contains('DynamicCollision.activate'));
    },
  );

  test(
    'harness records repeatable signatures and advisory comparisons',
    () async {
      const corpus = BenchmarkCorpus(
        id: 'tiny',
        kind: 'test',
        targetPath: '.',
        dartFiles: 2,
        sourceLines: 20,
        sourceBytes: 200,
        packageCount: 1,
        generated: true,
      );
      final benchmark = BenchmarkCase(
        name: 'tiny-analysis',
        category: 'analysis',
        checks: 'both',
        corpus: corpus,
        action: () async => const BenchmarkValue({'findings': 2}),
      );
      final measurements = await const BenchmarkHarness(
        warmups: 1,
        samples: 3,
      ).run([benchmark]);
      final report = BenchmarkReport(
        suite: 'test',
        warmups: 1,
        samples: 3,
        corpora: const [corpus],
        measurements: measurements,
      );
      report.compareWith({
        'schemaVersion': 1,
        'hyenaVersion': 'baseline',
        'suite': 'test',
        'runtime': runtimeMetadata(),
        'corpora': [corpus.toJson()],
        'benchmarks': [
          {
            'name': 'tiny-analysis',
            'category': 'analysis',
            'checks': 'both',
            'corpus': 'tiny',
            'medianMs': 1,
            'peakRssBytes': 1,
            'signature': {'findings': 2},
          },
        ],
      });

      expect(measurements.single.durationsMicros, hasLength(3));
      expect(measurements.single.signature, {'findings': 2});
      expect(measurements.single.comparison, containsPair('comparable', true));
      expect(
        measurements.single.comparison,
        containsPair('advisoryOnly', true),
      );
      expect(report.toJson(), containsPair('schemaVersion', 1));
    },
  );

  test('harness rejects comparisons when correctness signatures differ', () {
    const corpus = BenchmarkCorpus(
      id: 'tiny',
      kind: 'test',
      targetPath: '.',
      dartFiles: 1,
      sourceLines: 1,
      sourceBytes: 1,
      packageCount: 1,
      generated: true,
    );
    final measurement = BenchmarkMeasurement(
      benchmark: BenchmarkCase(
        name: 'tiny-analysis',
        category: 'analysis',
        checks: 'both',
        corpus: corpus,
        action: () async => const BenchmarkValue({'findings': 2}),
      ),
      durationsMicros: [1000],
      peakRssBytes: 1,
      peakRssGrowthBytes: 1,
      maxProcessRssBytes: 1,
      signature: const {'findings': 2},
    );
    final report = BenchmarkReport(
      suite: 'test',
      warmups: 1,
      samples: 1,
      corpora: const [corpus],
      measurements: [measurement],
    );

    report.compareWith({
      'schemaVersion': 1,
      'hyenaVersion': 'baseline',
      'suite': 'test',
      'runtime': runtimeMetadata(),
      'corpora': [corpus.toJson()],
      'benchmarks': [
        {
          'name': 'tiny-analysis',
          'category': 'analysis',
          'checks': 'both',
          'corpus': 'tiny',
          'medianMs': 1,
          'signature': {'findings': 3},
        },
      ],
    });

    expect(measurement.comparison, containsPair('comparable', false));
    expect(
      measurement.comparison?['compatibilityIssues'],
      contains('correctness signature'),
    );
    expect(measurement.comparison, isNot(contains('medianChangePercent')));
    expect(report.summary(), contains('incompatible'));
  });

  test('external corpus omits source artifacts excluded by analysis', () async {
    final target = Directory(p.join(scratch.path, 'external'))..createSync();
    for (final segments in [
      ['lib', 'source.dart'],
      ['lib', 'source.g.dart'],
      ['lib', 'source.freezed.dart'],
      ['lib', 'source.mocks.dart'],
      ['generated', 'source.dart'],
      ['.dart_tool', 'source.dart'],
      ['build', 'source.dart'],
    ]) {
      final file = File(p.joinAll([target.path, ...segments]));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('void source() {}');
    }

    final corpus = await BenchmarkCorpus.inspectExternal(
      target.path,
      label: 'external-test',
    );

    expect(corpus.dartFiles, 1);
    expect(corpus.sourceLines, 1);
  });

  test(
    'external benchmark refuses to write output inside its target',
    () async {
      final target = Directory(p.join(scratch.path, 'external'))..createSync();
      File(
        p.join(target.path, 'source.dart'),
      ).writeAsStringSync('void source() {}');
      final output = p.join(target.path, 'results', 'benchmark.json');

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'benchmark/benchmark.dart',
        '--target=${target.path}',
        '--checks=complexity',
        '--output=$output',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('--output must be outside the external benchmark target'),
      );
      expect(File(output).existsSync(), isFalse);

      if (!Platform.isWindows) {
        final alias = p.join(scratch.path, 'external-alias');
        await Link(alias).create(target.path);
        final aliasOutput = p.join(alias, 'results', 'benchmark.json');
        final aliasResult = await Process.run(Platform.resolvedExecutable, [
          'run',
          'benchmark/benchmark.dart',
          '--target=${target.path}',
          '--checks=complexity',
          '--output=$aliasOutput',
        ], workingDirectory: Directory.current.path);

        expect(aliasResult.exitCode, 1);
        expect(File(aliasOutput).existsSync(), isFalse);
      }
    },
  );
}
