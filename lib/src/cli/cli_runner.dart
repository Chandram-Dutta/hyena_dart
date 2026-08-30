import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../analyzer/analysis_runner.dart';
import '../models/analysis_finding.dart';
import '../models/analysis_result.dart';
import '../models/finding_baseline.dart';
import '../reporters/console_reporter.dart';
import '../reporters/html_reporter.dart';
import '../reporters/json_reporter.dart';
import '../reporters/markdown_reporter.dart';
import '../reporters/reporter.dart';
import '../reporters/sarif_reporter.dart';
import '../version.dart';

class HyenaCommandRunner extends CommandRunner<int> {
  HyenaCommandRunner()
    : super(
        'hyena',
        'A Flutter/Dart codebase analyzer for dead code and complexity metrics.',
      ) {
    argParser.addFlag(
      'version',
      help: 'Print the Hyena Dart version',
      negatable: false,
    );
    addCommand(AnalyzeCommand());
    addCommand(DeadCodeCommand());
    addCommand(ComplexityCommand());
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) {
    if (topLevelResults['version'] as bool) {
      print('hyena_dart $hyenaVersion');
      return Future.value(0);
    }
    return super.runCommand(topLevelResults);
  }
}

abstract class BaseAnalysisCommand extends Command<int> {
  void addCommonOptions() {
    argParser.addOption(
      'format',
      abbr: 'f',
      help: 'Output format',
      allowed: ['console', 'json', 'markdown', 'html', 'sarif'],
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
    argParser.addOption(
      'baseline',
      help: 'Suppress findings recorded in a Hyena baseline file',
    );
    argParser.addOption(
      'write-baseline',
      help: 'Write current findings to a Hyena baseline file',
    );
    argParser.addMultiOption(
      'fail-on',
      help: 'Return exit code 1 for selected finding categories',
      allowed: ['dead-code', 'complexity'],
      splitCommas: true,
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
      'sarif' => SarifReporter(),
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

  Future<AnalysisResult> applyBaselineOptions(
    AnalysisResult result,
    ArgResults results,
  ) async {
    final baselinePath = results['baseline'] as String?;
    final writeBaselinePath = results['write-baseline'] as String?;
    if (baselinePath != null && writeBaselinePath != null) {
      throw UsageException(
        '--baseline and --write-baseline cannot be used together.',
        usage,
      );
    }
    if (writeBaselinePath != null) {
      await FindingBaseline.fromResult(result).write(writeBaselinePath);
    }
    if (baselinePath != null) {
      return (await FindingBaseline.load(baselinePath)).apply(result);
    }
    return result;
  }

  int resultExitCode(AnalysisResult result, ArgResults results) {
    final failOn = (results['fail-on'] as List<String>).toSet();
    if (failOn.isEmpty) return 0;
    return AnalysisFinding.fromResult(
          result,
        ).any((finding) => failOn.contains(finding.category))
        ? 1
        : 0;
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
    argParser.addFlag(
      'ignore-exports',
      help: 'Preserve exported public APIs from dead-code findings',
      defaultsTo: false,
    );
    argParser.addFlag(
      'ignore-private',
      help: 'Ignore private entities',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    final targetPath = getTargetPath();
    var result = await const AnalysisRunner().analyze(
      targetPath,
      configPath: argResults!['config'] as String?,
      includeDeadCode: argResults!['dead-code'] as bool,
      includeComplexity: argResults!['complexity'] as bool,
      configure: (config) {
        if (argResults!.wasParsed('ignore-exports')) {
          config = config.copyWith(
            ignoreExports: argResults!['ignore-exports'] as bool,
          );
        }
        if (argResults!.wasParsed('ignore-private')) {
          config = config.copyWith(
            ignorePrivate: argResults!['ignore-private'] as bool,
          );
        }
        return config;
      },
    );
    result = await applyBaselineOptions(result, argResults!);

    final reporter = getReporter(argResults!);
    final output = await reporter.generate(result);
    await outputResult(output, argResults!);
    return resultExitCode(result, argResults!);
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
      help: 'Preserve exported public APIs from dead-code findings',
      defaultsTo: false,
    );
    argParser.addFlag(
      'ignore-private',
      help: 'Ignore private entities',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    final targetPath = getTargetPath();
    var result = await const AnalysisRunner().analyze(
      targetPath,
      configPath: argResults!['config'] as String?,
      includeComplexity: false,
      configure: (config) {
        if (argResults!.wasParsed('ignore-exports')) {
          config = config.copyWith(
            ignoreExports: argResults!['ignore-exports'] as bool,
          );
        }
        if (argResults!.wasParsed('ignore-private')) {
          config = config.copyWith(
            ignorePrivate: argResults!['ignore-private'] as bool,
          );
        }
        return config;
      },
    );
    result = await applyBaselineOptions(result, argResults!);

    final reporter = getReporter(argResults!);
    final output = await reporter.generate(result);
    await outputResult(output, argResults!);
    return resultExitCode(result, argResults!);
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
  Future<int> run() async {
    final targetPath = getTargetPath();
    var result = await const AnalysisRunner().analyze(
      targetPath,
      configPath: argResults!['config'] as String?,
      includeDeadCode: false,
      configure: (config) {
        if (argResults!.wasParsed('threshold')) {
          final threshold = int.tryParse(argResults!['threshold'] as String);
          if (threshold == null || threshold < 0) {
            throw UsageException(
              '--threshold must be a non-negative integer.',
              usage,
            );
          }
          return config.copyWith(cyclomaticThreshold: threshold);
        }
        return config;
      },
    );
    result = await applyBaselineOptions(result, argResults!);

    final reporter = getReporter(argResults!);
    final output = await reporter.generate(result);
    await outputResult(output, argResults!);
    return resultExitCode(result, argResults!);
  }
}
