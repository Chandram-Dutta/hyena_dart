import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:hyena_dart/hyena_dart.dart';

import 'corpus.dart';

typedef BenchmarkAction = Future<BenchmarkValue> Function();

class BenchmarkValue {
  final Map<String, Object?> signature;

  const BenchmarkValue(this.signature);
}

class BenchmarkCase {
  final String name;
  final String category;
  final String checks;
  final BenchmarkCorpus corpus;
  final BenchmarkAction action;
  final Future<void> Function()? setup;
  final int operationsPerSample;
  final bool reportsThroughput;

  const BenchmarkCase({
    required this.name,
    required this.category,
    required this.checks,
    required this.corpus,
    required this.action,
    this.setup,
    this.operationsPerSample = 1,
    this.reportsThroughput = true,
  });
}

class BenchmarkMeasurement {
  final BenchmarkCase benchmark;
  final List<double> durationsMicros;
  final int peakRssBytes;
  final int peakRssGrowthBytes;
  final int maxProcessRssBytes;
  final Map<String, Object?> signature;
  Map<String, Object?>? comparison;

  BenchmarkMeasurement({
    required this.benchmark,
    required this.durationsMicros,
    required this.peakRssBytes,
    required this.peakRssGrowthBytes,
    required this.maxProcessRssBytes,
    required this.signature,
  });

  double get medianMicros => _median(durationsMicros);
  double get p95Micros => _percentile(durationsMicros, 95);
  double get minMicros => durationsMicros.reduce(math.min);

  double? get filesPerSecond {
    if (!benchmark.reportsThroughput || medianMicros == 0) return null;
    final files =
        (signature['files'] as num?)?.toDouble() ??
        benchmark.corpus.dartFiles.toDouble();
    return files * Duration.microsecondsPerSecond / medianMicros;
  }

  double? get linesPerSecond {
    if (!benchmark.reportsThroughput || medianMicros == 0) return null;
    final lines =
        (signature['lines'] as num?)?.toDouble() ??
        benchmark.corpus.sourceLines.toDouble();
    return lines * Duration.microsecondsPerSecond / medianMicros;
  }

  Map<String, Object?> toJson() => {
    'name': benchmark.name,
    'category': benchmark.category,
    'checks': benchmark.checks,
    'corpus': benchmark.corpus.id,
    'samples': durationsMicros.length,
    'operationsPerSample': benchmark.operationsPerSample,
    'durationsMicros': durationsMicros.map(_round).toList(),
    'medianMs': _round(medianMicros / 1000),
    'p95Ms': _round(p95Micros / 1000),
    'minMs': _round(minMicros / 1000),
    if (filesPerSecond case final value?) 'filesPerSecond': _round(value),
    if (linesPerSecond case final value?) 'linesPerSecond': _round(value),
    'peakRssBytes': peakRssBytes,
    'peakRssGrowthBytes': peakRssGrowthBytes,
    'maxProcessRssBytes': maxProcessRssBytes,
    'signature': signature,
    if (comparison != null) 'comparison': comparison,
  };
}

class BenchmarkHarness {
  final int warmups;
  final int samples;

  const BenchmarkHarness({required this.warmups, required this.samples});

  Future<List<BenchmarkMeasurement>> run(List<BenchmarkCase> benchmarks) async {
    final measurements = <BenchmarkMeasurement>[];
    for (final benchmark in benchmarks) {
      stdout.writeln('Running ${benchmark.name}...');
      if (benchmark.setup != null) await benchmark.setup!();
      measurements.add(await _runCase(benchmark));
      final measurement = measurements.last;
      stdout.writeln(
        '  median ${_formatMs(measurement.medianMicros)} | '
        'p95 ${_formatMs(measurement.p95Micros)} | '
        'peak RSS ${_formatBytes(measurement.peakRssBytes)}',
      );
    }
    return measurements;
  }

  Future<BenchmarkMeasurement> _runCase(BenchmarkCase benchmark) async {
    String? expectedSignature;
    Map<String, Object?>? signature;

    void validate(BenchmarkValue value) {
      final encoded = jsonEncode(value.signature);
      expectedSignature ??= encoded;
      if (encoded != expectedSignature) {
        throw StateError(
          '${benchmark.name} produced inconsistent correctness signatures.',
        );
      }
      signature = value.signature;
    }

    for (var index = 0; index < warmups; index++) {
      validate(await benchmark.action());
    }

    final durations = <double>[];
    var peakRss = ProcessInfo.currentRss;
    var peakGrowth = 0;
    for (var sample = 0; sample < samples; sample++) {
      final rssBefore = ProcessInfo.currentRss;
      var samplePeak = rssBefore;
      final sampler = Timer.periodic(const Duration(milliseconds: 5), (_) {
        samplePeak = math.max(samplePeak, ProcessInfo.currentRss);
      });
      final stopwatch = Stopwatch()..start();
      try {
        for (
          var operation = 0;
          operation < benchmark.operationsPerSample;
          operation++
        ) {
          validate(await benchmark.action());
        }
      } finally {
        stopwatch.stop();
        sampler.cancel();
      }
      samplePeak = math.max(samplePeak, ProcessInfo.currentRss);
      peakRss = math.max(peakRss, samplePeak);
      peakGrowth = math.max(peakGrowth, samplePeak - rssBefore);
      durations.add(
        stopwatch.elapsedMicroseconds / benchmark.operationsPerSample,
      );
    }

    return BenchmarkMeasurement(
      benchmark: benchmark,
      durationsMicros: durations,
      peakRssBytes: peakRss,
      peakRssGrowthBytes: peakGrowth,
      maxProcessRssBytes: ProcessInfo.maxRss,
      signature: signature ?? const {},
    );
  }
}

class BenchmarkReport {
  final String suite;
  final int warmups;
  final int samples;
  final List<BenchmarkCorpus> corpora;
  final List<BenchmarkMeasurement> measurements;
  final Map<String, Object?> runtime;
  final DateTime generatedAt;

  BenchmarkReport({
    required this.suite,
    required this.warmups,
    required this.samples,
    required this.corpora,
    required this.measurements,
  }) : runtime = runtimeMetadata(),
       generatedAt = DateTime.now().toUtc();

  void compareWith(Map<String, Object?> baseline) {
    final baselineRuntime = (baseline['runtime'] as Map?)
        ?.cast<String, Object?>();
    final compatible =
        baselineRuntime != null &&
        baselineRuntime['operatingSystem'] == runtime['operatingSystem'] &&
        baselineRuntime['architecture'] == runtime['architecture'] &&
        baselineRuntime['dartVersion'] == runtime['dartVersion'] &&
        baselineRuntime['processors'] == runtime['processors'];
    final entries = (baseline['benchmarks'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.cast<String, Object?>())
        .where((entry) => entry['name'] is String)
        .fold<Map<String, Map<String, Object?>>>({}, (map, entry) {
          map[entry['name'] as String] = entry;
          return map;
        });
    final baselineCorpora = (baseline['corpora'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.cast<String, Object?>())
        .where((entry) => entry['id'] is String)
        .fold<Map<String, Map<String, Object?>>>({}, (map, entry) {
          map[entry['id'] as String] = entry;
          return map;
        });
    for (final measurement in measurements) {
      final previous = entries[measurement.benchmark.name];
      final baselineMedian = (previous?['medianMs'] as num?)?.toDouble();
      final baselineRssGrowth = (previous?['peakRssGrowthBytes'] as num?)
          ?.toDouble();
      if (baselineMedian == null || baselineMedian <= 0) continue;
      final currentCorpus = measurement.benchmark.corpus.toJson();
      final previousCorpus = baselineCorpora[measurement.benchmark.corpus.id];
      final previousSignature = (previous?['signature'] as Map?)
          ?.cast<String, Object?>();
      final compatibilityIssues = <String>[
        if (baseline['schemaVersion'] != 1) 'schema',
        if (baseline['suite'] != suite) 'suite',
        if (previous?['category'] != measurement.benchmark.category) 'category',
        if (previous?['checks'] != measurement.benchmark.checks) 'checks',
        if (previous?['corpus'] != measurement.benchmark.corpus.id) 'corpus',
        if (!_jsonEquivalent(previousCorpus, currentCorpus)) 'corpus metadata',
        if (!_jsonEquivalent(previousSignature, measurement.signature))
          'correctness signature',
      ];
      if (compatibilityIssues.isNotEmpty) {
        measurement.comparison = {
          'baselineVersion': baseline['hyenaVersion'] as String? ?? 'unknown',
          'environmentCompatible': compatible,
          'comparable': false,
          'compatibilityIssues': compatibilityIssues,
          'advisoryOnly': true,
        };
        continue;
      }
      measurement.comparison = {
        'baselineVersion': baseline['hyenaVersion'] as String? ?? 'unknown',
        'environmentCompatible': compatible,
        'comparable': true,
        'medianChangePercent': _round(
          ((measurement.medianMicros / 1000) - baselineMedian) /
              baselineMedian *
              100,
        ),
        if (baselineRssGrowth != null && baselineRssGrowth > 0)
          'peakRssGrowthChangePercent': _round(
            (measurement.peakRssGrowthBytes - baselineRssGrowth) /
                baselineRssGrowth *
                100,
          ),
        'advisoryOnly': true,
      };
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'hyenaVersion': hyenaVersion,
    'suite': suite,
    'warmups': warmups,
    'samples': samples,
    'runtime': runtime,
    'corpora': corpora.map((corpus) => corpus.toJson()).toList(),
    'benchmarks': measurements
        .map((measurement) => measurement.toJson())
        .toList(),
  };

  String summary() {
    final buffer = StringBuffer()
      ..writeln('Hyena Dart $hyenaVersion benchmark results')
      ..writeln('Suite: $suite | warmups: $warmups | samples: $samples')
      ..writeln(
        'Runtime: ${runtime['operatingSystem']} '
        '${runtime['architecture']}, ${runtime['processors']} CPUs',
      )
      ..writeln()
      ..writeln(
        '${'Benchmark'.padRight(32)} '
        '${'Median'.padLeft(10)} '
        '${'p95'.padLeft(10)} '
        '${'Files/s'.padLeft(10)} '
        '${'RSS growth'.padLeft(12)} '
        '${'vs baseline'.padLeft(12)}',
      );
    for (final measurement in measurements) {
      final change = measurement.comparison?['medianChangePercent'] as num?;
      final comparisonLabel = measurement.comparison?['comparable'] == false
          ? 'incompatible'
          : change == null
          ? '-'
          : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%';
      buffer.writeln(
        '${measurement.benchmark.name.padRight(32)} '
        '${_formatMs(measurement.medianMicros).padLeft(10)} '
        '${_formatMs(measurement.p95Micros).padLeft(10)} '
        '${_formatRate(measurement.filesPerSecond).padLeft(10)} '
        '${_formatBytes(measurement.peakRssGrowthBytes).padLeft(12)} '
        '${comparisonLabel.padLeft(12)}',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'Timing comparisons are advisory until repeated runner baselines are '
        'stable.',
      );
    return buffer.toString();
  }
}

bool _jsonEquivalent(Object? first, Object? second) {
  if (first is Map && second is Map) {
    if (first.length != second.length) return false;
    return first.entries.every(
      (entry) =>
          second.containsKey(entry.key) &&
          _jsonEquivalent(entry.value, second[entry.key]),
    );
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_jsonEquivalent(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
}

Map<String, Object?> runtimeMetadata() {
  final metadata = <String, Object?>{
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'architecture': Abi.current().toString(),
    'dartVersion': Platform.version,
    'processors': Platform.numberOfProcessors,
  };
  if (Platform.environment['GITHUB_SHA'] case final revision?) {
    metadata['sourceRevision'] = revision;
  }
  return metadata;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _percentile(List<double> values, int percentile) {
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile / 100).ceil();
  return sorted[index];
}

double _round(num value) => double.parse(value.toStringAsFixed(3));

String _formatMs(double micros) => '${(micros / 1000).toStringAsFixed(1)}ms';

String _formatRate(double? value) =>
    value == null ? '-' : value.toStringAsFixed(1);

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
