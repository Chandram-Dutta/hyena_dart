import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:hyena_dart/src/mcp/hyena_mcp_server.dart';
import 'package:hyena_dart/src/mcp/mcp_analysis_service.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'root',
      help: 'Workspace root that MCP analysis targets are confined to',
      valueHelp: 'directory',
    )
    ..addFlag('help', abbr: 'h', help: 'Show this help text', negatable: false);

  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      stdout.writeln('Usage: hyena_mcp --root <directory>\n\n${parser.usage}');
      return;
    }
    if (results.rest.isNotEmpty) {
      throw const FormatException('Unexpected positional arguments.');
    }

    final rootPath = results['root'] as String?;
    if (rootPath == null || rootPath.isEmpty) {
      throw const FormatException('--root is required.');
    }

    final analysisService = await McpAnalysisService.create(rootPath);
    final server = HyenaMcpServer(
      stdioChannel(input: stdin, output: stdout),
      analysisService: analysisService,
    );
    await server.done;
  } on ArgParserException catch (error) {
    _reportUsageError(error.message, parser);
  } on FormatException catch (error) {
    _reportUsageError(error.message, parser);
  } on ArgumentError catch (error) {
    stderr.writeln('hyena_mcp: ${error.message}');
    exitCode = 64;
  }
}

void _reportUsageError(String message, ArgParser parser) {
  stderr.writeln('hyena_mcp: $message\n\n${parser.usage}');
  exitCode = 64;
}
