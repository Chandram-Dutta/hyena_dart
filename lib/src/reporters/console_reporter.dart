import '../models/analysis_result.dart';
import '../models/code_entity.dart';
import 'reporter.dart';

class ConsoleReporter implements Reporter {
  final bool useColors;

  ConsoleReporter({this.useColors = true});

  String _red(String text) => useColors ? '\x1B[31m$text\x1B[0m' : text;
  String _green(String text) => useColors ? '\x1B[32m$text\x1B[0m' : text;
  String _yellow(String text) => useColors ? '\x1B[33m$text\x1B[0m' : text;
  String _bold(String text) => useColors ? '\x1B[1m$text\x1B[0m' : text;
  String _dim(String text) => useColors ? '\x1B[2m$text\x1B[0m' : text;

  @override
  Future<String> generate(AnalysisResult result) async {
    final buffer = StringBuffer();

    buffer.writeln();
    buffer.writeln(
      _bold('═══════════════════════════════════════════════════════════════'),
    );
    buffer.writeln(
      _bold('                    HYENA CODE ANALYSIS REPORT                  '),
    );
    buffer.writeln(
      _bold('═══════════════════════════════════════════════════════════════'),
    );
    buffer.writeln();
    buffer.writeln('${_dim("Target:")} ${result.targetPath}');
    buffer.writeln('${_dim("Duration:")} ${result.duration.inMilliseconds}ms');
    buffer.writeln();

    if (result.deadCodeReport != null) {
      _writeDeadCodeSection(buffer, result);
    }

    if (result.complexityReport != null) {
      _writeComplexitySection(buffer, result);
    }

    return buffer.toString();
  }

  void _writeDeadCodeSection(StringBuffer buffer, AnalysisResult result) {
    final report = result.deadCodeReport!;

    buffer.writeln(
      _bold('───────────────────────────────────────────────────────────────'),
    );
    buffer.writeln(
      _bold('                         DEAD CODE REPORT                       '),
    );
    buffer.writeln(
      _bold('───────────────────────────────────────────────────────────────'),
    );
    buffer.writeln();

    buffer.writeln(
      '${_dim("Total declarations:")} ${report.totalDeclarations}',
    );
    buffer.writeln(
      '${_dim("Unused entities:")} ${_colorizeCount(report.unusedCount)}',
    );
    buffer.writeln(
      '${_dim("Dead code percentage:")} ${_colorizePercentage(report.deadCodePercentage)}',
    );
    buffer.writeln();

    if (report.unusedEntities.isEmpty) {
      buffer.writeln(_green('✓ No dead code detected!'));
      buffer.writeln();
      return;
    }

    final grouped = report.groupedByType;
    for (final type in EntityType.values) {
      final entities = grouped[type];
      if (entities == null || entities.isEmpty) continue;

      buffer.writeln(
        _yellow('${_typeEmoji(type)} ${_pluralize(type, entities.length)}:'),
      );
      for (final entity in entities.take(20)) {
        buffer.writeln('  ${_dim("•")} ${entity.fullName}');
        buffer.writeln('    ${_dim(entity.filePath)}');
      }
      if (entities.length > 20) {
        buffer.writeln(_dim('    ... and ${entities.length - 20} more'));
      }
      buffer.writeln();
    }
  }

  void _writeComplexitySection(StringBuffer buffer, AnalysisResult result) {
    final report = result.complexityReport!;

    buffer.writeln(
      _bold('───────────────────────────────────────────────────────────────'),
    );
    buffer.writeln(
      _bold('                      COMPLEXITY REPORT                         '),
    );
    buffer.writeln(
      _bold('───────────────────────────────────────────────────────────────'),
    );
    buffer.writeln();

    buffer.writeln('${_dim("Files analyzed:")} ${report.totalFiles}');
    buffer.writeln('${_dim("Functions analyzed:")} ${report.totalFunctions}');
    buffer.writeln('${_dim("Total lines:")} ${report.totalLines}');
    buffer.writeln();

    final highComplexity = report.highComplexityFunctions;
    if (highComplexity.isEmpty) {
      buffer.writeln(_green('✓ No high complexity functions detected!'));
      buffer.writeln();
      return;
    }

    buffer.writeln(_yellow('⚠ High complexity functions (> 10):'));
    buffer.writeln();

    for (final func in highComplexity.take(20)) {
      final complexityColor = _getComplexityColor(func.cyclomaticComplexity);
      buffer.writeln('  ${_bold(func.fullName)}');
      buffer.writeln(
        '    ${_dim("Cyclomatic Complexity:")} ${complexityColor(func.cyclomaticComplexity.toString())}',
      );
      buffer.writeln('    ${_dim("Lines of Code:")} ${func.linesOfCode}');
      buffer.writeln('    ${_dim("Max Nesting:")} ${func.maxNestingLevel}');
      buffer.writeln('    ${_dim("Parameters:")} ${func.parameterCount}');
      buffer.writeln(
        '    ${_dim("Maintainability Index:")} ${func.maintainabilityIndex.toStringAsFixed(1)}',
      );
      buffer.writeln('    ${_dim(func.filePath)}');
      buffer.writeln();
    }

    if (highComplexity.length > 20) {
      buffer.writeln(
        _dim(
          '... and ${highComplexity.length - 20} more high complexity functions',
        ),
      );
      buffer.writeln();
    }
  }

  String _colorizeCount(int count) {
    if (count == 0) return _green('0');
    if (count < 10) return _yellow(count.toString());
    return _red(count.toString());
  }

  String _colorizePercentage(double percentage) {
    final formatted = '${percentage.toStringAsFixed(1)}%';
    if (percentage < 5) return _green(formatted);
    if (percentage < 15) return _yellow(formatted);
    return _red(formatted);
  }

  String Function(String) _getComplexityColor(int complexity) {
    if (complexity <= 10) return _green;
    if (complexity <= 20) return _yellow;
    return _red;
  }

  String _typeEmoji(EntityType type) => switch (type) {
    EntityType.classDecl => '📦',
    EntityType.abstractClass => '📦',
    EntityType.mixin => '🧩',
    EntityType.extension => '🔧',
    EntityType.extensionType => '🔧',
    EntityType.enum_ => '📋',
    EntityType.enumValue => '  •',
    EntityType.function => '⚡',
    EntityType.method => '🔹',
    EntityType.getter => '👁',
    EntityType.setter => '✏️',
    EntityType.topLevelVariable => '📌',
    EntityType.field => '📎',
    EntityType.typedef => '📝',
    EntityType.import => '📥',
  };

  String _pluralize(EntityType type, int count) {
    final label = switch (type) {
      EntityType.classDecl => 'class',
      EntityType.abstractClass => 'abstract class',
      EntityType.mixin => 'mixin',
      EntityType.extension => 'extension',
      EntityType.extensionType => 'extension type',
      EntityType.enum_ => 'enum',
      EntityType.enumValue => 'enum value',
      EntityType.function => 'function',
      EntityType.method => 'method',
      EntityType.getter => 'getter',
      EntityType.setter => 'setter',
      EntityType.topLevelVariable => 'variable',
      EntityType.field => 'field',
      EntityType.typedef => 'typedef',
      EntityType.import => 'import',
    };
    final suffix = count == 1 ? '' : (label.endsWith('s') ? 'es' : 's');
    return '$count unused $label$suffix';
  }
}
