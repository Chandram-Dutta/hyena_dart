import '../models/analysis_result.dart';
import '../models/code_entity.dart';
import 'reporter.dart';

class MarkdownReporter implements Reporter {
  @override
  Future<String> generate(AnalysisResult result) async {
    final buffer = StringBuffer();

    buffer.writeln('# Hyena Code Analysis Report');
    buffer.writeln();
    buffer.writeln('**Target:** `${result.targetPath}`');
    buffer.writeln(
      '**Analysis Duration:** ${result.duration.inMilliseconds}ms',
    );
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

    buffer.writeln('## Dead Code Report');
    buffer.writeln();
    buffer.writeln('| Metric | Value |');
    buffer.writeln('|--------|-------|');
    buffer.writeln('| Total Declarations | ${report.totalDeclarations} |');
    buffer.writeln('| Unused Entities | ${report.unusedCount} |');
    buffer.writeln(
      '| Dead Code Percentage | ${report.deadCodePercentage.toStringAsFixed(1)}% |',
    );
    buffer.writeln();

    if (report.unusedEntities.isEmpty) {
      buffer.writeln('> ✅ No dead code detected!');
      buffer.writeln();
      return;
    }

    final grouped = report.groupedByType;
    for (final type in EntityType.values) {
      final entities = grouped[type];
      if (entities == null || entities.isEmpty) continue;

      buffer.writeln('### Unused ${_pluralize(type, entities.length)}');
      buffer.writeln();
      buffer.writeln('| Name | File | Line |');
      buffer.writeln('|------|------|------|');
      for (final entity in entities) {
        buffer.writeln(
          '| `${entity.fullName}` | ${entity.filePath} | ${entity.line} |',
        );
      }
      buffer.writeln();
    }
  }

  void _writeComplexitySection(StringBuffer buffer, AnalysisResult result) {
    final report = result.complexityReport!;

    buffer.writeln('## Complexity Report');
    buffer.writeln();
    buffer.writeln('| Metric | Value |');
    buffer.writeln('|--------|-------|');
    buffer.writeln('| Files Analyzed | ${report.totalFiles} |');
    buffer.writeln('| Functions Analyzed | ${report.totalFunctions} |');
    buffer.writeln('| Total Lines | ${report.totalLines} |');
    buffer.writeln(
      '| High Complexity Functions | ${report.highComplexityFunctions.length} |',
    );
    buffer.writeln();

    final highComplexity = report.highComplexityFunctions;
    if (highComplexity.isEmpty) {
      buffer.writeln('> ✅ No high complexity functions detected!');
      buffer.writeln();
      return;
    }

    buffer.writeln('### High Complexity Functions (> 10)');
    buffer.writeln();
    buffer.writeln('| Function | Cyclomatic | LOC | Nesting | Params | MI |');
    buffer.writeln('|----------|------------|-----|---------|--------|-----|');
    for (final func in highComplexity) {
      buffer.writeln(
        '| `${func.fullName}` | ${func.cyclomaticComplexity} | ${func.linesOfCode} | ${func.maxNestingLevel} | ${func.parameterCount} | ${func.maintainabilityIndex.toStringAsFixed(1)} |',
      );
    }
    buffer.writeln();

    buffer.writeln('### All Files');
    buffer.writeln();
    for (final file in report.files) {
      buffer.writeln('<details>');
      buffer.writeln(
        '<summary>${file.filePath} (${file.functions.length} functions)</summary>',
      );
      buffer.writeln();
      buffer.writeln('- **Total Lines:** ${file.totalLines}');
      buffer.writeln('- **Code Lines:** ${file.codeLines}');
      buffer.writeln('- **Comment Lines:** ${file.commentLines}');
      buffer.writeln('- **Blank Lines:** ${file.blankLines}');
      buffer.writeln(
        '- **Avg Complexity:** ${file.averageCyclomaticComplexity.toStringAsFixed(1)}',
      );
      buffer.writeln('- **Max Complexity:** ${file.maxCyclomaticComplexity}');
      buffer.writeln();
      buffer.writeln('</details>');
      buffer.writeln();
    }
  }

  String _pluralize(EntityType type, int count) {
    final label = switch (type) {
      EntityType.classDecl => 'Classes',
      EntityType.abstractClass => 'Abstract Classes',
      EntityType.mixin => 'Mixins',
      EntityType.extension => 'Extensions',
      EntityType.extensionType => 'Extension Types',
      EntityType.enum_ => 'Enums',
      EntityType.enumValue => 'Enum Values',
      EntityType.function => 'Functions',
      EntityType.method => 'Methods',
      EntityType.getter => 'Getters',
      EntityType.setter => 'Setters',
      EntityType.topLevelVariable => 'Variables',
      EntityType.field => 'Fields',
      EntityType.typedef => 'Typedefs',
      EntityType.import => 'Imports',
    };
    return '$label ($count)';
  }
}
