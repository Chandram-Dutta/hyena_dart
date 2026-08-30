import '../models/analysis_result.dart';
import '../models/analysis_path.dart';
import '../models/code_entity.dart';
import 'reporter.dart';

class MarkdownReporter implements Reporter {
  @override
  Future<String> generate(AnalysisResult result) async {
    final buffer = StringBuffer();
    final rootPath = analysisRootForTarget(result.targetPath);

    buffer.writeln('# Hyena Code Analysis Report');
    buffer.writeln();
    buffer.writeln(
      '**Target:** `${relativeAnalysisPath(result.targetPath, rootPath)}`',
    );
    buffer.writeln(
      '**Analysis Duration:** ${result.duration.inMilliseconds}ms',
    );
    buffer.writeln();

    if (result.isWorkspace) {
      buffer.writeln(
        '**Workspace packages:** ${result.packageAnalyses.length}',
      );
      buffer.writeln();
      for (final packageResult in result.packageAnalyses) {
        buffer.writeln(
          '## Package `${packageResult.packageName ?? relativeAnalysisPath(packageResult.targetPath, rootPath)}`',
        );
        buffer.writeln();
        buffer.writeln(
          '**Path:** `${relativeAnalysisPath(packageResult.targetPath, rootPath)}`',
        );
        buffer.writeln();
        if (packageResult.deadCodeReport != null) {
          _writeDeadCodeSection(buffer, packageResult, rootPath);
        }
        if (packageResult.complexityReport != null) {
          _writeComplexitySection(buffer, packageResult, rootPath);
        }
      }
      return buffer.toString();
    }

    if (result.deadCodeReport != null) {
      _writeDeadCodeSection(buffer, result, rootPath);
    }

    if (result.complexityReport != null) {
      _writeComplexitySection(buffer, result, rootPath);
    }

    return buffer.toString();
  }

  void _writeDeadCodeSection(
    StringBuffer buffer,
    AnalysisResult result,
    String rootPath,
  ) {
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
          '| `${entity.fullName}` | ${relativeAnalysisPath(entity.filePath, rootPath)} | ${entity.line} |',
        );
      }
      buffer.writeln();
    }
  }

  void _writeComplexitySection(
    StringBuffer buffer,
    AnalysisResult result,
    String rootPath,
  ) {
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
    buffer.writeln(
      '| High Nesting Functions | ${report.highNestingFunctions.length} |',
    );
    buffer.writeln(
      '| High Parameter Functions | ${report.highParameterFunctions.length} |',
    );
    buffer.writeln();

    final violations = report.thresholdViolations;
    if (violations.isEmpty) {
      buffer.writeln('> ✅ No complexity threshold violations detected!');
      buffer.writeln();
      return;
    }

    buffer.writeln('### Complexity Threshold Violations');
    buffer.writeln();
    buffer.writeln(
      'Thresholds: cyclomatic > ${report.cyclomaticThreshold}, '
      'nesting > ${report.maxNestingLevel}, '
      'parameters > ${report.maxParameters}.',
    );
    buffer.writeln();
    buffer.writeln('| Function | Cyclomatic | LOC | Nesting | Params | MI |');
    buffer.writeln('|----------|------------|-----|---------|--------|-----|');
    for (final func in violations) {
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
        '<summary>${relativeAnalysisPath(file.filePath, rootPath)} (${file.functions.length} functions)</summary>',
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
      EntityType.constructor => 'Constructors',
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
