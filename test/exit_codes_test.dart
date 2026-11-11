import 'dart:async';
import 'dart:io';

import 'package:hyena_dart/src/cli/cli_main.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late String source;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('hyena_exit_codes_');
    File(
      p.join(fixture.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: exit_codes_fixture\n');
    source = p.join(fixture.path, 'sample.dart');
    File(source).writeAsStringSync('void target() {}\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  test('exit code constants are stable', () {
    expect(HyenaExitCode.ok, 0);
    expect(HyenaExitCode.findings, 1);
    expect(HyenaExitCode.toolError, 2);
    expect(HyenaExitCode.usage, 64);
  });

  group('hyena CLI', () {
    test('exits 0 for a successful run without --fail-on', () async {
      final result = await _runCli(['complexity', source, '--threshold=0']);
      expect(result.exitCode, HyenaExitCode.ok, reason: result.errors);
    });

    test('exits 0 for --help and --version', () async {
      expect((await _runCli(['--help'])).exitCode, HyenaExitCode.ok);
      expect((await _runCli(['--version'])).exitCode, HyenaExitCode.ok);
    });

    test('exits 1 when findings trip --fail-on', () async {
      final result = await _runCli([
        'complexity',
        source,
        '--threshold=0',
        '--fail-on=complexity',
      ]);
      expect(result.exitCode, HyenaExitCode.findings, reason: result.errors);
    });

    test('exits 0 when findings stay below the --fail-on threshold', () async {
      final result = await _runCli([
        'complexity',
        source,
        '--threshold=20',
        '--fail-on=complexity',
      ]);
      expect(result.exitCode, HyenaExitCode.ok, reason: result.errors);
    });

    test('exits 0 when findings exist only outside --fail-on', () async {
      File(
        p.join(fixture.path, 'lib', 'unused.dart'),
      ).createSync(recursive: true);
      File(
        p.join(fixture.path, 'lib', 'unused.dart'),
      ).writeAsStringSync('void unusedHelper() {}\n');

      final deadCode = await _runCli([
        'dead-code',
        fixture.path,
        '--format=json',
        '--fail-on=dead-code',
      ]);
      expect(
        deadCode.exitCode,
        HyenaExitCode.findings,
        reason: deadCode.errors,
      );

      final result = await _runCli([
        'analyze',
        fixture.path,
        '--format=json',
        '--fail-on=complexity',
      ]);
      expect(result.exitCode, HyenaExitCode.ok, reason: result.errors);
    });

    test('exits 2 when the target path does not exist', () async {
      final result = await _runCli([
        'analyze',
        p.join(fixture.path, 'missing'),
      ]);
      expect(result.exitCode, HyenaExitCode.toolError);
      expect(result.errors, contains('Target path does not exist'));
    });

    test('exits 2 when the config file does not exist', () async {
      final result = await _runCli([
        'complexity',
        source,
        '--config=${p.join(fixture.path, 'missing.yaml')}',
      ]);
      expect(result.exitCode, HyenaExitCode.toolError);
      expect(result.errors, contains('Configuration file does not exist'));
    });

    test('exits 2 when the config file is invalid', () async {
      final config = File(p.join(fixture.path, 'hyena.yaml'))
        ..writeAsStringSync('hyena:\n  exclude: not-a-list\n');
      final result = await _runCli([
        'complexity',
        source,
        '--config=${config.path}',
      ]);
      expect(result.exitCode, HyenaExitCode.toolError);
      expect(result.errors, contains('hyena.exclude must be a list'));
    });

    test('exits 2 when the baseline file is unreadable', () async {
      final baseline = File(p.join(fixture.path, 'baseline.json'))
        ..writeAsStringSync('{not json');
      final result = await _runCli([
        'complexity',
        source,
        '--baseline=${baseline.path}',
      ]);
      expect(result.exitCode, HyenaExitCode.toolError);
    });

    test('exits 2 when the report cannot be written', () async {
      final result = await _runCli([
        'complexity',
        source,
        '--output=${p.join(fixture.path, 'missing-dir', 'report.txt')}',
      ]);
      expect(result.exitCode, HyenaExitCode.toolError);
    });

    test('exits 2 for findings and a tool error together', () async {
      final result = await _runCli([
        'complexity',
        source,
        '--threshold=0',
        '--fail-on=complexity',
        '--config=${p.join(fixture.path, 'missing.yaml')}',
      ]);
      expect(result.exitCode, HyenaExitCode.toolError);
    });

    test('exits 64 for usage errors', () async {
      for (final arguments in [
        ['unknown-command'],
        ['analyze', '--unknown-flag'],
        ['analyze', '--fail-on=unknown'],
        ['complexity', source, '--threshold=-1'],
        ['analyze', fixture.path, fixture.path],
        ['analyze', fixture.path, '--no-dead-code', '--no-complexity'],
      ]) {
        final result = await _runCli(arguments);
        expect(
          result.exitCode,
          HyenaExitCode.usage,
          reason: '$arguments: ${result.errors}',
        );
      }
    });

    // Usage errors through bin/ are covered by test/version_test.dart.
    test('bin/hyena_dart.dart propagates tool-error exit code', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/hyena_dart.dart',
        'complexity',
        source,
        '--config=${p.join(fixture.path, 'missing.yaml')}',
      ]);
      expect(
        result.exitCode,
        HyenaExitCode.toolError,
        reason: result.stderr as String,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test(
    'hyena_mcp exits 64 for usage errors and 2 for startup failures',
    () async {
      final usage = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/hyena_mcp.dart',
      ]);
      expect(usage.exitCode, HyenaExitCode.usage);

      final startup = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/hyena_mcp.dart',
        '--root=${p.join(fixture.path, 'missing')}',
      ]);
      expect(
        startup.exitCode,
        HyenaExitCode.toolError,
        reason: startup.stderr as String,
      );
      expect(
        startup.stderr as String,
        contains('MCP workspace root does not exist'),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<({String output, String errors, int exitCode})> _runCli(
  List<String> arguments,
) async {
  final output = <String>[];
  final errors = StringBuffer();
  final exitCode = await runZoned(
    () => runHyenaCli(arguments, errorSink: errors),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, message) => output.add(message),
    ),
  );
  return (
    output: output.join('\n'),
    errors: errors.toString(),
    exitCode: exitCode,
  );
}
