import 'dart:io';

import 'package:hyena_dart/src/version.dart';
import 'package:yaml/yaml.dart';

void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final pubspecVersion = pubspec['version'];
  if (pubspecVersion != hyenaVersion) {
    stderr.writeln(
      'Version mismatch: pubspec.yaml has $pubspecVersion, but Hyena reports '
      '$hyenaVersion.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Hyena version $hyenaVersion is consistent.');
}
