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
}
