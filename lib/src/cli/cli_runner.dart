import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../analyzer/complexity_analyzer.dart';
import '../analyzer/dead_code_analyzer.dart';
import '../config/analyzer_config.dart';
import '../models/analysis_result.dart';
import '../reporters/console_reporter.dart';
import '../reporters/html_reporter.dart';
import '../reporters/json_reporter.dart';
import '../reporters/markdown_reporter.dart';
import '../reporters/reporter.dart';

class HyenaCommandRunner extends CommandRunner<void> {
  HyenaCommandRunner()
    : super(
        'hyena',
        'A Flutter/Dart codebase analyzer for dead code and complexity metrics.',
      ) {
    addCommand(AnalyzeCommand());
    addCommand(DeadCodeCommand());
    addCommand(ComplexityCommand());
  }
}

abstract class BaseAnalysisCommand extends Command<void> {
  void addCommonOptions() {
    argParser.addOption(
      'format',
      abbr: 'f',
      help: 'Output format',
      allowed: ['console', 'json', 'markdown', 'html'],
      defaultsTo: 'console',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output file path (if not specified, prints to stdout)',
    );
    argParser.addOption(
      'config',
      abbr: 'c',
      help: 'Path to configuration file',
    );
    argParser.addFlag(
      'no-color',
      help: 'Disable colored output',
      negatable: false,
    );
  }

  String getTargetPath() {
    return argResults!.rest.isEmpty ? '.' : argResults!.rest.first;
  }

  Reporter getReporter(ArgResults results) {
    final format = results['format'] as String;
    final noColor = results['no-color'] as bool;

    return switch (format) {
      'json' => JsonReporter(),
      'markdown' => MarkdownReporter(),
      'html' => HtmlReporter(),
      _ => ConsoleReporter(useColors: !noColor),
    };
  }

  Future<void> outputResult(String content, ArgResults results) async {
    final outputPath = results['output'] as String?;
    if (outputPath != null) {
      await File(outputPath).writeAsString(content);
      print('Report written to: $outputPath');
    } else {
      print(content);
    }
  }
}

class AnalyzeCommand extends BaseAnalysisCommand {
  @override
  String get name => 'analyze';

  @override
  String get description => 'Run full analysis (dead code + complexity)';

  AnalyzeCommand() {
    addCommonOptions();
    argParser.addFlag(
      'dead-code',
      help: 'Include dead code analysis',
      defaultsTo: true,
    );
    argParser.addFlag(
      'complexity',
      help: 'Include complexity analysis',
      defaultsTo: true,
    );
  }

  @override
  Future<void> run() async {
    final targetPath = getTargetPath();
    final config = await AnalyzerConfig.load(argResults!['config'] as String?);
    final stopwatch = Stopwatch()..start();

    final includeDeadCode = argResults!['dead-code'] as bool;
    final includeComplexity = argResults!['complexity'] as bool;

    final deadCodeReport = includeDeadCode
        ? await DeadCodeAnalyzer(config).analyze(targetPath)
        : null;

    final complexityReport = includeComplexity
        ? await ComplexityAnalyzer(config).analyze(targetPath)
        : null;

    stopwatch.stop();

    final result = AnalysisResult(
      deadCodeReport: deadCodeReport,
      complexityReport: complexityReport,
      targetPath: targetPath,
      duration: stopwatch.elapsed,
    );

    final reporter = getReporter(argResults!);
    final output = await reporter.generate(result);
    await outputResult(output, argResults!);
  }
}

class DeadCodeCommand extends BaseAnalysisCommand {
  @override
  String get name => 'dead-code';

  @override
  String get description => 'Analyze codebase for unused code';

  DeadCodeCommand() {
    addCommonOptions();
    argParser.addFlag(
      'ignore-exports',
      help: 'Ignore exported entities',
      defaultsTo: true,
    );
    argParser.addFlag(
      'ignore-private',
      help: 'Ignore private entities',
      defaultsTo: false,
    );
  }

  @override
  Future<void> run() async {
    final targetPath = getTargetPath();
    var config = await AnalyzerConfig.load(argResults!['config'] as String?);

    config = config.copyWith(
      ignoreExports: argResults!['ignore-exports'] as bool,
      ignorePrivate: argResults!['ignore-private'] as bool,
    );

    final stopwatch = Stopwatch()..start();
    final deadCodeReport = await DeadCodeAnalyzer(config).analyze(targetPath);
    stopwatch.stop();

    final result = AnalysisResult(
      deadCodeReport: deadCodeReport,
      targetPath: targetPath,
      duration: stopwatch.elapsed,
    );

    final reporter = getReporter(argResults!);
    final output = await reporter.generate(result);
    await outputResult(output, argResults!);
  }
}

class ComplexityCommand extends BaseAnalysisCommand {
  @override
  String get name => 'complexity';

  @override
  String get description => 'Analyze code complexity metrics';

  ComplexityCommand() {
    addCommonOptions();
    argParser.addOption(
      'threshold',
      abbr: 't',
      help: 'Cyclomatic complexity threshold for warnings',
      defaultsTo: '20',
    );
  }

  @override
  Future<void> run() async {
    final targetPath = getTargetPath();
    var config = await AnalyzerConfig.load(argResults!['config'] as String?);

    final threshold = int.tryParse(argResults!['threshold'] as String) ?? 20;
    config = config.copyWith(cyclomaticThreshold: threshold);

    final stopwatch = Stopwatch()..start();
    final complexityReport = await ComplexityAnalyzer(
      config,
    ).analyze(targetPath);
    stopwatch.stop();

    final result = AnalysisResult(
      complexityReport: complexityReport,
      targetPath: targetPath,
      duration: stopwatch.elapsed,
    );

    final reporter = getReporter(argResults!);
    final output = await reporter.generate(result);
    await outputResult(output, argResults!);
  }
}
