import '../models/analysis_result.dart';
import '../models/code_entity.dart';
import 'reporter.dart';

class HtmlReporter implements Reporter {
  @override
  Future<String> generate(AnalysisResult result) async {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln(
      '  <meta name="viewport" content="width=device-width, initial-scale=1.0">',
    );
    buffer.writeln('  <title>Hyena Code Analysis Report</title>');
    buffer.writeln('  <style>');
    buffer.writeln(_css);
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('  <div class="container">');
    buffer.writeln('    <header>');
    buffer.writeln('      <h1>🐺 Hyena Code Analysis Report</h1>');
    buffer.writeln(
      '      <p class="meta">Target: <code>${result.targetPath}</code> | Duration: ${result.duration.inMilliseconds}ms</p>',
    );
    buffer.writeln('    </header>');

    if (result.deadCodeReport != null) {
      _writeDeadCodeSection(buffer, result);
    }

    if (result.complexityReport != null) {
      _writeComplexitySection(buffer, result);
    }

    buffer.writeln('  </div>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  void _writeDeadCodeSection(StringBuffer buffer, AnalysisResult result) {
    final report = result.deadCodeReport!;

    buffer.writeln('    <section class="report-section">');
    buffer.writeln('      <h2>☠️ Dead Code Report</h2>');
    buffer.writeln('      <div class="summary-cards">');
    buffer.writeln('        <div class="card">');
    buffer.writeln(
      '          <div class="card-value">${report.totalDeclarations}</div>',
    );
    buffer.writeln(
      '          <div class="card-label">Total Declarations</div>',
    );
    buffer.writeln('        </div>');
    buffer.writeln(
      '        <div class="card ${_getCountClass(report.unusedCount)}">',
    );
    buffer.writeln(
      '          <div class="card-value">${report.unusedCount}</div>',
    );
    buffer.writeln('          <div class="card-label">Unused Entities</div>');
    buffer.writeln('        </div>');
    buffer.writeln(
      '        <div class="card ${_getPercentageClass(report.deadCodePercentage)}">',
    );
    buffer.writeln(
      '          <div class="card-value">${report.deadCodePercentage.toStringAsFixed(1)}%</div>',
    );
    buffer.writeln('          <div class="card-label">Dead Code</div>');
    buffer.writeln('        </div>');
    buffer.writeln('      </div>');

    if (report.unusedEntities.isEmpty) {
      buffer.writeln(
        '      <div class="success-message">✅ No dead code detected!</div>',
      );
    } else {
      buffer.writeln('      <div class="entity-list">');
      final grouped = report.groupedByFile;
      for (final entry in grouped.entries) {
        buffer.writeln('        <details>');
        buffer.writeln(
          '          <summary>${entry.key} (${entry.value.length} issues)</summary>',
        );
        buffer.writeln('          <table>');
        buffer.writeln(
          '            <thead><tr><th>Type</th><th>Name</th><th>Line</th></tr></thead>',
        );
        buffer.writeln('            <tbody>');
        for (final entity in entry.value) {
          buffer.writeln('              <tr>');
          buffer.writeln(
            '                <td><span class="badge badge-${_getTypeBadgeClass(entity.type)}">${entity.typeLabel}</span></td>',
          );
          buffer.writeln(
            '                <td><code>${entity.fullName}</code></td>',
          );
          buffer.writeln('                <td>${entity.line}</td>');
          buffer.writeln('              </tr>');
        }
        buffer.writeln('            </tbody>');
        buffer.writeln('          </table>');
        buffer.writeln('        </details>');
      }
      buffer.writeln('      </div>');
    }

    buffer.writeln('    </section>');
  }

  void _writeComplexitySection(StringBuffer buffer, AnalysisResult result) {
    final report = result.complexityReport!;

    buffer.writeln('    <section class="report-section">');
    buffer.writeln('      <h2>📊 Complexity Report</h2>');
    buffer.writeln('      <div class="summary-cards">');
    buffer.writeln('        <div class="card">');
    buffer.writeln(
      '          <div class="card-value">${report.totalFiles}</div>',
    );
    buffer.writeln('          <div class="card-label">Files</div>');
    buffer.writeln('        </div>');
    buffer.writeln('        <div class="card">');
    buffer.writeln(
      '          <div class="card-value">${report.totalFunctions}</div>',
    );
    buffer.writeln('          <div class="card-label">Functions</div>');
    buffer.writeln('        </div>');
    buffer.writeln('        <div class="card">');
    buffer.writeln(
      '          <div class="card-value">${report.totalLines}</div>',
    );
    buffer.writeln('          <div class="card-label">Total Lines</div>');
    buffer.writeln('        </div>');
    buffer.writeln(
      '        <div class="card ${_getCountClass(report.highComplexityFunctions.length)}">',
    );
    buffer.writeln(
      '          <div class="card-value">${report.highComplexityFunctions.length}</div>',
    );
    buffer.writeln('          <div class="card-label">High Complexity</div>');
    buffer.writeln('        </div>');
    buffer.writeln('      </div>');

    final highComplexity = report.highComplexityFunctions;
    if (highComplexity.isEmpty) {
      buffer.writeln(
        '      <div class="success-message">✅ No high complexity functions!</div>',
      );
    } else {
      buffer.writeln('      <h3>⚠️ High Complexity Functions</h3>');
      buffer.writeln('      <table>');
      buffer.writeln('        <thead>');
      buffer.writeln(
        '          <tr><th>Function</th><th>Cyclomatic</th><th>LOC</th><th>Nesting</th><th>Params</th><th>MI</th></tr>',
      );
      buffer.writeln('        </thead>');
      buffer.writeln('        <tbody>');
      for (final func in highComplexity) {
        buffer.writeln('          <tr>');
        buffer.writeln(
          '            <td><code>${func.fullName}</code><br><small>${func.filePath}</small></td>',
        );
        buffer.writeln(
          '            <td class="${_getComplexityClass(func.cyclomaticComplexity)}">${func.cyclomaticComplexity}</td>',
        );
        buffer.writeln('            <td>${func.linesOfCode}</td>');
        buffer.writeln('            <td>${func.maxNestingLevel}</td>');
        buffer.writeln('            <td>${func.parameterCount}</td>');
        buffer.writeln(
          '            <td>${func.maintainabilityIndex.toStringAsFixed(1)}</td>',
        );
        buffer.writeln('          </tr>');
      }
      buffer.writeln('        </tbody>');
      buffer.writeln('      </table>');
    }

    buffer.writeln('    </section>');
  }

  String _getCountClass(int count) {
    if (count == 0) return 'success';
    if (count < 10) return 'warning';
    return 'danger';
  }

  String _getPercentageClass(double percentage) {
    if (percentage < 5) return 'success';
    if (percentage < 15) return 'warning';
    return 'danger';
  }

  String _getComplexityClass(int complexity) {
    if (complexity <= 10) return 'success';
    if (complexity <= 20) return 'warning';
    return 'danger';
  }

  String _getTypeBadgeClass(EntityType type) => switch (type) {
    EntityType.classDecl || EntityType.abstractClass => 'class',
    EntityType.mixin ||
    EntityType.extension ||
    EntityType.extensionType => 'mixin',
    EntityType.enum_ || EntityType.enumValue => 'enum',
    EntityType.function || EntityType.method => 'function',
    EntityType.getter || EntityType.setter => 'accessor',
    EntityType.topLevelVariable || EntityType.field => 'variable',
    EntityType.typedef => 'typedef',
    EntityType.import => 'import',
  };

  static const _css = '''
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; color: #333; line-height: 1.6; }
    .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
    header { text-align: center; margin-bottom: 30px; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border-radius: 10px; }
    header h1 { font-size: 2em; margin-bottom: 10px; }
    .meta { opacity: 0.9; }
    .meta code { background: rgba(255,255,255,0.2); padding: 2px 6px; border-radius: 4px; }
    .report-section { background: white; border-radius: 10px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .report-section h2 { margin-bottom: 20px; color: #333; border-bottom: 2px solid #eee; padding-bottom: 10px; }
    .report-section h3 { margin: 20px 0 15px; color: #666; }
    .summary-cards { display: flex; gap: 15px; flex-wrap: wrap; margin-bottom: 20px; }
    .card { flex: 1; min-width: 120px; background: #f8f9fa; border-radius: 8px; padding: 15px; text-align: center; }
    .card-value { font-size: 2em; font-weight: bold; color: #333; }
    .card-label { font-size: 0.85em; color: #666; }
    .card.success { background: #d4edda; }
    .card.success .card-value { color: #155724; }
    .card.warning { background: #fff3cd; }
    .card.warning .card-value { color: #856404; }
    .card.danger { background: #f8d7da; }
    .card.danger .card-value { color: #721c24; }
    .success-message { background: #d4edda; color: #155724; padding: 15px; border-radius: 8px; text-align: center; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; }
    th, td { padding: 10px; text-align: left; border-bottom: 1px solid #eee; }
    th { background: #f8f9fa; font-weight: 600; }
    td code { background: #f1f3f4; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
    td small { color: #666; display: block; margin-top: 4px; }
    td.success { color: #155724; font-weight: bold; }
    td.warning { color: #856404; font-weight: bold; }
    td.danger { color: #721c24; font-weight: bold; }
    details { margin: 10px 0; border: 1px solid #eee; border-radius: 8px; }
    summary { padding: 10px 15px; cursor: pointer; background: #f8f9fa; border-radius: 8px; }
    summary:hover { background: #e9ecef; }
    details[open] summary { border-radius: 8px 8px 0 0; }
    details table { margin: 0; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.8em; font-weight: 500; }
    .badge-class { background: #cce5ff; color: #004085; }
    .badge-mixin { background: #d4edda; color: #155724; }
    .badge-enum { background: #fff3cd; color: #856404; }
    .badge-function { background: #e2e3e5; color: #383d41; }
    .badge-accessor { background: #d1ecf1; color: #0c5460; }
    .badge-variable { background: #f8d7da; color: #721c24; }
    .badge-typedef { background: #e7e8ea; color: #5a5a5a; }
    .badge-import { background: #f5c6cb; color: #721c24; }
  ''';
}
