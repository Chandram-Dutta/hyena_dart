import 'dart:io';

import 'package:hyena_dart/src/cli/cli_main.dart';

/// Exit codes: 0 ok, 1 findings tripped `--fail-on`, 2 tool error,
/// 64 usage error. See [HyenaExitCode].
Future<void> main(List<String> arguments) async {
  exitCode = await runHyenaCli(arguments);
}
