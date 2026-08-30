import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:hyena_dart/hyena_dart.dart';

Future<void> main(List<String> arguments) async {
  final runner = HyenaCommandRunner();
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } on ArgumentError catch (error) {
    stderr.writeln('hyena: ${error.message}');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('hyena: ${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'hyena: ${error.message}${error.path == null ? '' : ': ${error.path}'}',
    );
    exitCode = 1;
  } on StateError catch (error) {
    stderr.writeln('hyena: ${error.message}');
    exitCode = 1;
  }
}
