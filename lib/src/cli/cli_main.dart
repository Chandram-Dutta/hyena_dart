import 'dart:io';

import 'package:args/command_runner.dart';

import 'cli_runner.dart';

/// Process exit codes used by the `hyena_dart` and `hyena_mcp` executables.
abstract final class HyenaExitCode {
  /// Analysis completed and no finding tripped `--fail-on`.
  static const int ok = 0;

  /// Analysis completed and findings matched a `--fail-on` category.
  static const int findings = 1;

  /// Hyena could not complete: bad configuration, unreadable or invalid
  /// paths, analysis failures, or unexpected internal errors.
  static const int toolError = 2;

  /// Invalid command-line usage (unknown command or flag, bad option value).
  /// Matches `EX_USAGE` from BSD `sysexits.h`.
  static const int usage = 64;
}

/// Runs the Hyena CLI with [arguments] and returns the process exit code.
///
/// Diagnostics are written to [errorSink] (defaults to [stderr]). Report
/// output is printed through `print`, as before.
Future<int> runHyenaCli(List<String> arguments, {StringSink? errorSink}) async {
  final err = errorSink ?? stderr;
  try {
    return await HyenaCommandRunner().run(arguments) ?? HyenaExitCode.ok;
  } on UsageException catch (error) {
    err.writeln(error);
    return HyenaExitCode.usage;
  } on ArgumentError catch (error) {
    err.writeln('hyena: ${error.message}');
    return HyenaExitCode.toolError;
  } on FormatException catch (error) {
    err.writeln('hyena: ${error.message}');
    return HyenaExitCode.toolError;
  } on FileSystemException catch (error) {
    err.writeln(
      'hyena: ${error.message}${error.path == null ? '' : ': ${error.path}'}',
    );
    return HyenaExitCode.toolError;
  } on StateError catch (error) {
    err.writeln('hyena: ${error.message}');
    return HyenaExitCode.toolError;
  } catch (error, stackTrace) {
    err
      ..writeln('hyena: unexpected error: $error')
      ..writeln(stackTrace);
    return HyenaExitCode.toolError;
  }
}
