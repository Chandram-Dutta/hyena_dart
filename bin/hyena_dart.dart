import 'dart:io';

import 'package:hyena_dart/hyena_dart.dart';

Future<void> main(List<String> arguments) async {
  final runner = HyenaCommandRunner();
  exitCode = await runner.run(arguments) ?? 0;
}
