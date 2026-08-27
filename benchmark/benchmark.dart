import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:hyena_dart/hyena_dart.dart';
import 'package:hyena_dart/src/mcp/mcp_analysis_service.dart';
import 'package:path/path.dart' as p;

import 'src/corpus.dart';
import 'src/harness.dart';

Future<void> main(List<String> arguments) async {
  final parser = _parser();
  late final _BenchmarkOptions options;
  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      stdout.writeln(_usage(parser));
      return;
    }
    options = _BenchmarkOptions.fromResults(results);
  } on ArgParserException catch (error) {
    _usageError(error.message, parser);
    return;
  } on FormatException catch (error) {
    _usageError(error.message, parser);
    return;
  } on ArgumentError catch (error) {
    stderr.writeln('benchmark: ${error.message}');
    exitCode = 64;
    return;
  }

  try {
    await _run(options);
  } on FormatException catch (error) {
    _benchmarkFailure(error.message);
  } on StateError catch (error) {
    _benchmarkFailure(error.message);
  } on ArgumentError catch (error) {
    _benchmarkFailure(error.message);
  }
}

void _benchmarkFailure(Object? message) {
  stderr.writeln('benchmark failed: $message');
  exitCode = 1;
}

Future<void> _run(_BenchmarkOptions options) async {
  final scratch = await Directory.systemTemp.createTemp('hyena_benchmark_');
  try {
    final corpora = options.targetPath == null
        ? await _generateCorpora(scratch, options.suite)
        : [
            await BenchmarkCorpus.inspectExternal(
              options.targetPath!,
              label: options.label,
            ),
          ];
    if (options.targetPath != null && options.outputPath != null) {
      final outputPath = await _canonicalOutputPath(options.outputPath!);
      final targetPath = corpora.single.targetPath;
      if (p.equals(outputPath, targetPath) ||
          p.isWithin(targetPath, outputPath)) {
        throw ArgumentError(
          '--output must be outside the external benchmark target.',
        );
      }
    }
    final benchmarks = options.targetPath == null
        ? await _generatedBenchmarks(corpora, scratch, options.suite)
        : [_analysisCase(corpora.single, options.checks)];

    stdout.writeln(
      'Prepared ${corpora.length} corpus/corpora with '
      '${corpora.fold<int>(0, (sum, corpus) => sum + corpus.dartFiles)} '
      'Dart files.',
    );
    final harness = BenchmarkHarness(
      warmups: options.warmups,
      samples: options.samples,
    );
    final measurements = await harness.run(benchmarks);
    final report = BenchmarkReport(
      suite: options.targetPath == null ? options.suite : 'external',
      warmups: options.warmups,
      samples: options.samples,
      corpora: corpora,
      measurements: measurements,
    );
    if (options.baselinePath != null) {
      report.compareWith(await _loadJson(options.baselinePath!));
    }

    stdout
      ..writeln()
      ..write(report.summary());
    if (options.outputPath != null) {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
      );
      stdout.writeln('Wrote benchmark JSON to ${output.path}');
    }
    if (options.keepCorpus && options.targetPath == null) {
      stdout.writeln('Generated corpus retained at ${scratch.path}');
      return;
    }
  } finally {
    if (!options.keepCorpus || options.targetPath != null) {
      await scratch.delete(recursive: true);
    }
  }
}

Future<List<BenchmarkCorpus>> _generateCorpora(
  Directory scratch,
  String suite,
) async {
  final generator = BenchmarkCorpusGenerator(scratch);
  final corpora = <BenchmarkCorpus>[
    await generator.singlePackage(id: 'single_100', fileCount: 100),
    await generator.workspace(
      id: 'workspace_100',
      packages: 4,
      filesPerPackage: 25,
    ),
  ];
  if (suite == 'full') {
    corpora.addAll([
      await generator.singlePackage(id: 'single_500', fileCount: 500),
      await generator.singlePackage(id: 'single_1000', fileCount: 1000),
      await generator.workspace(
        id: 'workspace_1000',
        packages: 20,
        filesPerPackage: 50,
      ),
    ]);
  }
  return corpora;
}

Future<List<BenchmarkCase>> _generatedBenchmarks(
  List<BenchmarkCorpus> corpora,
  Directory scratch,
  String suite,
) async {
  final single = corpora.singleWhere((corpus) => corpus.id == 'single_100');
  final workspace = corpora.singleWhere(
    (corpus) => corpus.id == 'workspace_100',
  );
  final benchmarks = <BenchmarkCase>[
    _analysisCase(single, 'complexity'),
    _analysisCase(single, 'dead-code'),
    _analysisCase(single, 'both'),
    _analysisCase(workspace, 'none', name: 'workspace-discovery-100'),
    _analysisCase(workspace, 'both'),
  ];

  AnalysisResult? reportResult;
  Future<void> prepareReport() async {
    reportResult ??= await const AnalysisRunner().analyze(single.targetPath);
  }

  BenchmarkValue? jsonReportSignature;
  Future<void> prepareJsonReport() async {
    await prepareReport();
    jsonReportSignature ??= _jsonTextValue(
      await JsonReporter(prettyPrint: false).generate(reportResult!),
    );
  }

  benchmarks.addAll([
    BenchmarkCase(
      name: 'json-report-100',
      category: 'report',
      checks: 'both',
      corpus: single,
      setup: prepareJsonReport,
      operationsPerSample: 20,
      reportsThroughput: false,
      action: () async {
        final output = await JsonReporter(
          prettyPrint: false,
        ).generate(reportResult!);
        _textValue(output);
        return jsonReportSignature!;
      },
    ),
    BenchmarkCase(
      name: 'sarif-report-100',
      category: 'report',
      checks: 'both',
      corpus: single,
      setup: prepareReport,
      operationsPerSample: 20,
      reportsThroughput: false,
      action: () async =>
          _textValue(await SarifReporter().generate(reportResult!)),
    ),
  ]);

  McpAnalysisService? service;
  benchmarks.add(
    BenchmarkCase(
      name: 'mcp-end-to-end-100',
      category: 'mcp',
      checks: 'both',
      corpus: single,
      setup: () async {
        service ??= await McpAnalysisService.create(single.targetPath);
      },
      action: () async {
        final result = await service!.analyze(checks: 'both');
        return BenchmarkValue({
          'checks': result['checks'],
          'summary': result['summary'],
        });
      },
    ),
  );
  benchmarks.add(_cliCase(single, scratch));

  if (suite == 'full') {
    final single500 = corpora.singleWhere(
      (corpus) => corpus.id == 'single_500',
    );
    final single1000 = corpora.singleWhere(
      (corpus) => corpus.id == 'single_1000',
    );
    final workspace1000 = corpora.singleWhere(
      (corpus) => corpus.id == 'workspace_1000',
    );
    benchmarks.addAll([
      _analysisCase(single500, 'both'),
      _analysisCase(single1000, 'both'),
      _analysisCase(workspace1000, 'none', name: 'workspace-discovery-1000'),
      _analysisCase(workspace1000, 'dead-code'),
      _analysisCase(workspace1000, 'both'),
    ]);
  }
  return benchmarks;
}

BenchmarkCase _analysisCase(
  BenchmarkCorpus corpus,
  String checks, {
  String? name,
}) {
  final includeDeadCode = checks == 'both' || checks == 'dead-code';
  final includeComplexity = checks == 'both' || checks == 'complexity';
  return BenchmarkCase(
    name: name ?? '${checks.replaceAll('-', '_')}-${corpus.id}',
    category: checks == 'none' ? 'discovery' : 'analysis',
    checks: checks,
    corpus: corpus,
    reportsThroughput: checks != 'none',
    action: () async {
      final result = await const AnalysisRunner().analyze(
        corpus.targetPath,
        includeDeadCode: includeDeadCode,
        includeComplexity: includeComplexity,
      );
      return BenchmarkValue(
        _analysisSignature(
          result,
          corpus,
          includeDeadCode: includeDeadCode,
          includeComplexity: includeComplexity,
        ),
      );
    },
  );
}

BenchmarkCase _cliCase(BenchmarkCorpus corpus, Directory scratch) {
  final outputPath = p.join(scratch.path, 'cli-report.json');
  return BenchmarkCase(
    name: 'cli-process-complexity-100',
    category: 'cli',
    checks: 'complexity',
    corpus: corpus,
    action: () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/hyena_dart.dart',
        'complexity',
        corpus.targetPath,
        '--format=json',
        '--output=$outputPath',
      ], workingDirectory: _repositoryRoot);
      if (result.exitCode != 0) {
        throw StateError(
          'CLI benchmark failed (${result.exitCode}): ${result.stderr}',
        );
      }
      return BenchmarkValue(_jsonReportSignature(await _loadJson(outputPath)));
    },
  );
}

Map<String, Object?> _analysisSignature(
  AnalysisResult result,
  BenchmarkCorpus corpus, {
  required bool includeDeadCode,
  required bool includeComplexity,
}) {
  final packages = result.packageAnalyses.toList();
  if (corpus.packageCount != null && packages.length != corpus.packageCount) {
    throw StateError(
      '${corpus.id} expected ${corpus.packageCount} package results, got '
      '${packages.length}.',
    );
  }
  final deadReports = packages
      .map((package) => package.deadCodeReport)
      .whereType<DeadCodeReport>()
      .toList();
  final complexityReports = packages
      .map((package) => package.complexityReport)
      .whereType<ComplexityReport>()
      .toList();
  final declarations = deadReports.fold<int>(
    0,
    (sum, report) => sum + report.totalDeclarations,
  );
  final unused = deadReports.fold<int>(
    0,
    (sum, report) => sum + report.unusedCount,
  );
  final files = complexityReports.fold<int>(
    0,
    (sum, report) => sum + report.totalFiles,
  );
  if (corpus.generated &&
      includeDeadCode &&
      (declarations == 0 || unused == 0)) {
    throw StateError('${corpus.id} did not exercise dead-code findings.');
  }
  if (corpus.generated && includeComplexity && files != corpus.dartFiles) {
    throw StateError(
      '${corpus.id} expected ${corpus.dartFiles} complexity files, got $files.',
    );
  }
  return {
    'packageCount': packages.length,
    if (includeDeadCode) ...{
      'totalDeclarations': declarations,
      'unusedDeclarations': unused,
    },
    if (includeComplexity) ...{
      'files': files,
      'functions': complexityReports.fold<int>(
        0,
        (sum, report) => sum + report.totalFunctions,
      ),
      'lines': complexityReports.fold<int>(
        0,
        (sum, report) => sum + report.totalLines,
      ),
      'thresholdViolations': complexityReports.fold<int>(
        0,
        (sum, report) => sum + report.thresholdViolations.length,
      ),
    },
  };
}

Map<String, Object?> _jsonReportSignature(Map<String, Object?> report) {
  final workspace = (report['workspace'] as Map?)?.cast<String, Object?>();
  final deadCode = (report['deadCode'] as Map?)?.cast<String, Object?>();
  final complexity = (report['complexity'] as Map?)?.cast<String, Object?>();
  final signature = <String, Object?>{};
  if (workspace != null) signature['workspace'] = workspace;
  if (deadCode?['summary'] case final Map summary) {
    signature['deadCode'] = summary.cast<String, Object?>();
  }
  if (complexity?['summary'] case final Map summary) {
    signature['complexity'] = summary.cast<String, Object?>();
  }
  return signature;
}

BenchmarkValue _textValue(String value) => BenchmarkValue({
  'bytes': utf8.encode(value).length,
  'fnv1a': _fnv1a(value),
});

BenchmarkValue _jsonTextValue(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('JSON reporter did not return a JSON map.');
  }
  return BenchmarkValue(_jsonReportSignature(decoded.cast<String, Object?>()));
}

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Future<Map<String, Object?>> _loadJson(String path) async {
  final file = File(path);
  if (!await file.exists()) throw ArgumentError('JSON file not found: $path');
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) throw FormatException('$path must contain a JSON map.');
  return decoded.cast<String, Object?>();
}

Future<String> _canonicalOutputPath(String path) async {
  var current = p.normalize(p.absolute(path));
  final unresolvedSegments = <String>[];
  while (await FileSystemEntity.type(current, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(current);
    if (p.equals(parent, current)) break;
    unresolvedSegments.insert(0, p.basename(current));
    current = parent;
  }
  final type = await FileSystemEntity.type(current, followLinks: false);
  final FileSystemEntity entity = switch (type) {
    FileSystemEntityType.directory => Directory(current),
    FileSystemEntityType.link => Link(current),
    _ => File(current),
  };
  final resolved = p.normalize(await entity.resolveSymbolicLinks());
  return p.normalize(p.joinAll([resolved, ...unresolvedSegments]));
}

ArgParser _parser() => ArgParser()
  ..addOption(
    'suite',
    allowed: ['quick', 'full'],
    defaultsTo: 'quick',
    help: 'Generated benchmark suite to run.',
  )
  ..addOption(
    'samples',
    defaultsTo: '3',
    help: 'Measured samples per benchmark.',
  )
  ..addOption(
    'warmups',
    defaultsTo: '1',
    help: 'Untimed warm-up runs per benchmark.',
  )
  ..addOption('output', help: 'Write structured benchmark JSON to this path.')
  ..addOption('baseline', help: 'Advisory baseline JSON to compare against.')
  ..addOption(
    'target',
    help: 'Analyze an existing repository read-only instead of generated data.',
  )
  ..addOption(
    'checks',
    allowed: ['both', 'dead-code', 'complexity'],
    defaultsTo: 'both',
    help: 'Checks used with --target.',
  )
  ..addOption(
    'label',
    defaultsTo: 'external-repository',
    help: 'Non-sensitive label used with --target.',
  )
  ..addFlag(
    'keep-corpus',
    negatable: false,
    help: 'Keep generated projects for local inspection.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

String _usage(ArgParser parser) =>
    '''
Usage: dart run benchmark/benchmark.dart [options]

${parser.usage}

Generated fixtures are deterministic and created outside measured sections.
--target reads an existing checkout but never runs its code or pub get.
''';

void _usageError(String message, ArgParser parser) {
  stderr.writeln('benchmark: $message\n\n${_usage(parser)}');
  exitCode = 64;
}

class _BenchmarkOptions {
  final String suite;
  final int samples;
  final int warmups;
  final String? outputPath;
  final String? baselinePath;
  final String? targetPath;
  final String checks;
  final String label;
  final bool keepCorpus;

  const _BenchmarkOptions({
    required this.suite,
    required this.samples,
    required this.warmups,
    required this.outputPath,
    required this.baselinePath,
    required this.targetPath,
    required this.checks,
    required this.label,
    required this.keepCorpus,
  });

  factory _BenchmarkOptions.fromResults(ArgResults results) {
    final samples = int.tryParse(results['samples'] as String);
    final warmups = int.tryParse(results['warmups'] as String);
    if (samples == null || samples < 1) {
      throw const FormatException('--samples must be a positive integer.');
    }
    if (warmups == null || warmups < 1) {
      throw const FormatException('--warmups must be a positive integer.');
    }
    final target = results['target'] as String?;
    if (target != null && results.wasParsed('suite')) {
      throw const FormatException('--suite cannot be combined with --target.');
    }
    return _BenchmarkOptions(
      suite: results['suite'] as String,
      samples: samples,
      warmups: warmups,
      outputPath: results['output'] as String?,
      baselinePath: results['baseline'] as String?,
      targetPath: target,
      checks: results['checks'] as String,
      label: results['label'] as String,
      keepCorpus: results['keep-corpus'] as bool,
    );
  }
}

final String _repositoryRoot = p.dirname(
  p.dirname(Platform.script.toFilePath()),
);
