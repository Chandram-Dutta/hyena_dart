import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('runtime version matches package metadata', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(pubspec['version'], hyenaVersion);
  });

  test('both executables report the package version', () async {
    for (final executable in ['hyena_dart.dart', 'hyena_mcp.dart']) {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/$executable',
        '--version',
      ]);
      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(result.stdout as String, contains(hyenaVersion));
    }
  });

  test(
    'CLI reports invalid invocations without unhandled exceptions',
    () async {
      final cases = <(List<String>, int, String)>[
        (
          ['run', 'bin/hyena_dart.dart', 'analyze', 'lib', 'test'],
          64,
          'Expected at most one target path',
        ),
        (
          [
            'run',
            'bin/hyena_dart.dart',
            'analyze',
            'lib',
            '--no-dead-code',
            '--no-complexity',
          ],
          64,
          'At least one of --dead-code or --complexity must be enabled',
        ),
        (
          ['run', 'bin/hyena_dart.dart', 'analyze', 'does-not-exist'],
          1,
          'Target path does not exist',
        ),
      ];

      for (final (arguments, expectedExitCode, expectedMessage) in cases) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          arguments,
        );
        final stderr = result.stderr as String;
        expect(result.exitCode, expectedExitCode, reason: stderr);
        expect(stderr, contains(expectedMessage));
        expect(stderr, isNot(contains('Unhandled exception')));
        expect(stderr, isNot(contains('#0')));
      }
    },
  );
}
