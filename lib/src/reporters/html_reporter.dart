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
    buffer.writeln('      <h1>Hyena Code Analysis Report</h1>');
    buffer.writeln(
      '      <p class="meta">Target: <code>${result.targetPath}</code> • Duration: ${result.duration.inMilliseconds}ms</p>',
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
    buffer.writeln('      <h2>Dead Code Report</h2>');
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
        '      <div class="success-message">No dead code detected</div>',
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
    buffer.writeln('      <h2>Complexity Report</h2>');
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
        '      <div class="success-message">No high complexity functions</div>',
      );
    } else {
      buffer.writeln('      <h3>High Complexity Functions</h3>');
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
    * { 
      box-sizing: border-box; 
      margin: 0; 
      padding: 0; 
    }
    
    body { 
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; 
      background: #fafbfc; 
      color: #24292f; 
      line-height: 1.6; 
      padding: 2rem 1rem; 
    }
    
    .container { 
      max-width: 1200px; 
      margin: 0 auto; 
    }
    
    header { 
      margin-bottom: 2rem; 
      padding: 2rem 0; 
      border-bottom: 2px solid #e5e7eb;
    }
    
    header h1 { 
      font-size: 1.875rem; 
      font-weight: 600; 
      margin-bottom: 0.5rem; 
      color: #111827;
    }
    
    .meta { 
      font-size: 0.875rem; 
      color: #6b7280;
    }
    
    .meta code { 
      background: #f3f4f6; 
      padding: 0.125rem 0.375rem; 
      border-radius: 3px; 
      font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', monospace;
      font-size: 0.8125rem;
      color: #374151;
    }
    
    .report-section { 
      background: white; 
      border-radius: 6px; 
      padding: 1.5rem; 
      margin-bottom: 1.5rem; 
      border: 1px solid #e5e7eb;
    }
    
    .report-section h2 { 
      margin-bottom: 1.25rem; 
      color: #111827; 
      font-size: 1.25rem;
      font-weight: 600;
      padding-bottom: 0.75rem;
      border-bottom: 1px solid #e5e7eb;
    }
    
    .report-section h3 { 
      margin: 1.5rem 0 1rem; 
      color: #374151; 
      font-size: 1rem;
      font-weight: 600;
    }
    
    .summary-cards { 
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 1rem; 
      margin-bottom: 2rem; 
    }
    
    .card { 
      background: #fafbfc; 
      border-radius: 4px; 
      padding: 1rem; 
      text-align: center;
      border: 1px solid #d1d5db;
    }
    
    .card-value { 
      font-size: 2rem; 
      font-weight: 600; 
      color: #111827; 
      line-height: 1;
      margin-bottom: 0.375rem;
    }
    
    .card-label { 
      font-size: 0.8125rem; 
      color: #6b7280; 
      font-weight: 500;
    }
    
    .card.success { 
      background: #f0fdf4; 
      border-color: #86efac;
    }
    
    .card.success .card-value { 
      color: #15803d; 
    }
    
    .card.warning { 
      background: #fffbeb; 
      border-color: #fcd34d;
    }
    
    .card.warning .card-value { 
      color: #b45309; 
    }
    
    .card.danger { 
      background: #fef2f2; 
      border-color: #fca5a5;
    }
    
    .card.danger .card-value { 
      color: #dc2626; 
    }
    
    .success-message { 
      background: #f0fdf4; 
      color: #15803d; 
      padding: 0.875rem; 
      border-radius: 4px; 
      text-align: center; 
      font-weight: 500;
      border: 1px solid #86efac;
    }
    
    table { 
      width: 100%; 
      border-collapse: collapse; 
      margin-top: 1rem; 
    }
    
    th, td { 
      padding: 0.875rem 1rem; 
      text-align: left; 
      border-bottom: 1px solid #e5e7eb; 
    }
    
    th { 
      background: #fafbfc; 
      font-weight: 600; 
      font-size: 0.8125rem;
      color: #374151;
    }
    
    tbody tr:hover {
      background: #fafbfc;
    }
    
    td code { 
      background: #f3f4f6; 
      padding: 0.25rem 0.5rem; 
      border-radius: 4px; 
      font-size: 0.875rem; 
      font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', monospace;
      color: #374151;
      font-weight: 500;
    }
    
    td small { 
      color: #6b7280; 
      display: block; 
      margin-top: 0.375rem; 
      font-size: 0.8125rem;
    }
    
    td.success { 
      color: #047857; 
      font-weight: 600; 
    }
    
    td.warning { 
      color: #b45309; 
      font-weight: 600; 
    }
    
    td.danger { 
      color: #dc2626; 
      font-weight: 600; 
    }
    
    details { 
      margin: 0.5rem 0; 
      border: 1px solid #d1d5db; 
      border-radius: 4px; 
      overflow: hidden;
    }
    
    summary { 
      padding: 0.75rem 1rem; 
      cursor: pointer; 
      background: #fafbfc; 
      font-weight: 500;
      color: #374151;
      user-select: none;
      font-size: 0.875rem;
    }
    
    summary:hover { 
      background: #f3f4f6; 
    }
    
    details[open] summary { 
      border-bottom: 1px solid #d1d5db;
    }
    
    details table { 
      margin: 0; 
      border-radius: 0;
    }
    
    details table th {
      background: white;
    }
    
    .badge { 
      display: inline-block; 
      padding: 0.1875rem 0.5rem; 
      border-radius: 3px; 
      font-size: 0.6875rem; 
      font-weight: 500;
    }
    
    .badge-class { 
      background: #dbeafe; 
      color: #1e40af; 
    }
    
    .badge-mixin { 
      background: #d1fae5; 
      color: #047857; 
    }
    
    .badge-enum { 
      background: #fef3c7; 
      color: #b45309; 
    }
    
    .badge-function { 
      background: #e5e7eb; 
      color: #374151; 
    }
    
    .badge-accessor { 
      background: #cffafe; 
      color: #0e7490; 
    }
    
    .badge-variable { 
      background: #fce7f3; 
      color: #be185d; 
    }
    
    .badge-typedef { 
      background: #f3f4f6; 
      color: #4b5563; 
    }
    
    .badge-import { 
      background: #ffe4e6; 
      color: #be123c; 
    }
  ''';
}
