# Hyena Dart

A powerful Flutter/Dart codebase analyzer that detects dead code and calculates code complexity metrics. Built using the official Dart `analyzer` package for accurate AST-based analysis.

## Features

- **Dead Code Detection** - Find unused classes, functions, methods, enums, variables, fields, and typedefs
- **Complexity Metrics** - Cyclomatic complexity, lines of code, nesting levels, parameter count, maintainability index
- **Multiple Output Formats** - Console (colored), JSON, Markdown, HTML
- **Configurable** - Exclude patterns, thresholds, and analysis options via YAML config
- **CI/CD Ready** - JSON output for easy integration with build pipelines

## Installation

Add to your `pubspec.yaml` as a dev dependency:

```yaml
dev_dependencies:
  hyena_dart:
    path: /path/to/hyena_dart
```

Or run directly:

```bash
dart run bin/hyena_dart.dart <command> [options]
```

## Quick Start

```bash
# Analyze current directory
dart run bin/hyena_dart.dart analyze .

# Analyze specific path
dart run bin/hyena_dart.dart analyze lib

# Dead code analysis only
dart run bin/hyena_dart.dart dead-code lib

# Complexity analysis only
dart run bin/hyena_dart.dart complexity lib
```

## CLI Reference

### Commands

#### `analyze` - Full Analysis
Run both dead code and complexity analysis.

```bash
dart run bin/hyena_dart.dart analyze <path> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | `-f` | Output format: `console`, `json`, `markdown`, `html` | `console` |
| `--output` | `-o` | Output file path (prints to stdout if not specified) | - |
| `--config` | `-c` | Path to configuration file | - |
| `--no-color` | - | Disable colored output | `false` |
| `--dead-code` | - | Include dead code analysis | `true` |
| `--complexity` | - | Include complexity analysis | `true` |

**Examples:**
```bash
# Full analysis with HTML report
dart run bin/hyena_dart.dart analyze lib --format=html --output=report.html

# JSON output for CI/CD
dart run bin/hyena_dart.dart analyze lib --format=json --output=analysis.json

# Skip complexity analysis
dart run bin/hyena_dart.dart analyze lib --no-complexity
```

#### `dead-code` - Dead Code Analysis
Analyze codebase for unused code entities.

```bash
dart run bin/hyena_dart.dart dead-code <path> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | `-f` | Output format | `console` |
| `--output` | `-o` | Output file path | - |
| `--config` | `-c` | Path to configuration file | - |
| `--ignore-exports` | - | Ignore exported entities | `true` |
| `--ignore-private` | - | Ignore private entities | `false` |

**Examples:**
```bash
# Find all unused code including exports
dart run bin/hyena_dart.dart dead-code lib --no-ignore-exports

# Markdown report
dart run bin/hyena_dart.dart dead-code lib --format=markdown --output=dead-code.md
```

#### `complexity` - Complexity Analysis
Analyze code complexity metrics.

```bash
dart run bin/hyena_dart.dart complexity <path> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | `-f` | Output format | `console` |
| `--output` | `-o` | Output file path | - |
| `--config` | `-c` | Path to configuration file | - |
| `--threshold` | `-t` | Cyclomatic complexity threshold for warnings | `20` |

**Examples:**
```bash
# Set custom threshold
dart run bin/hyena_dart.dart complexity lib --threshold=15

# JSON output
dart run bin/hyena_dart.dart complexity lib --format=json
```

## Configuration

Create a `hyena.yaml` file in your project root:

```yaml
hyena:
  # Glob patterns to exclude from analysis
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.mocks.dart"
    - "**/generated/**"

  # Complexity thresholds
  complexity:
    cyclomatic_threshold: 20
    max_nesting: 5
    max_parameters: 6

  # Dead code options
  dead_code:
    ignore_main: true
    ignore_exports: true
    ignore_private: false
```

You can also add the configuration to your existing `analysis_options.yaml`:

```yaml
# Your existing linter rules...
linter:
  rules:
    - prefer_const_constructors

# Hyena configuration
hyena:
  exclude:
    - "**/*.g.dart"
  complexity:
    cyclomatic_threshold: 15
```

## Output Formats

### Console (Default)
Colored terminal output with summary and details.

### JSON
Machine-readable format for CI/CD integration:

```json
{
  "targetPath": "lib",
  "duration": "205ms",
  "deadCode": {
    "summary": {
      "totalDeclarations": 170,
      "unusedCount": 5,
      "deadCodePercentage": "2.94"
    },
    "unusedEntities": [...]
  },
  "complexity": {
    "summary": {
      "totalFiles": 17,
      "totalFunctions": 133,
      "highComplexityFunctions": 2
    },
    "files": [...]
  }
}
```

### Markdown
GitHub-friendly format with tables and collapsible sections.

### HTML
Visual report with styled cards, tables, and color-coded metrics.

## Metrics Explained

### Dead Code Detection
Detects the following unused entities:
- Classes (including abstract classes)
- Mixins and Extensions
- Enums and enum values
- Top-level and instance functions/methods
- Getters and setters
- Variables and fields
- Typedefs

### Complexity Metrics

| Metric | Description |
|--------|-------------|
| **Cyclomatic Complexity** | Number of linearly independent paths through code. Higher = more complex. |
| **Lines of Code (LOC)** | Non-blank lines in a function. |
| **Max Nesting Level** | Deepest level of nested control structures. |
| **Parameter Count** | Number of function parameters. |
| **Maintainability Index** | Composite score (0-100). Higher = more maintainable. |

### Complexity Thresholds

| Cyclomatic Complexity | Risk Level |
|-----------------------|------------|
| 1-10 | Low - Simple, easy to test |
| 11-20 | Moderate - More complex |
| 21-50 | High - Difficult to test |
| 50+ | Very High - Untestable, refactor recommended |

## Programmatic Usage

You can also use Hyena as a library:

```dart
import 'package:hyena_dart/hyena_dart.dart';

void main() async {
  final config = AnalyzerConfig(
    cyclomaticThreshold: 15,
    ignoreExports: true,
  );

  // Dead code analysis
  final deadCodeAnalyzer = DeadCodeAnalyzer(config);
  final deadCodeReport = await deadCodeAnalyzer.analyze('./lib');
  print('Unused entities: ${deadCodeReport.unusedCount}');

  // Complexity analysis
  final complexityAnalyzer = ComplexityAnalyzer(config);
  final complexityReport = await complexityAnalyzer.analyze('./lib');
  print('High complexity functions: ${complexityReport.highComplexityFunctions.length}');

  // Generate reports
  final result = AnalysisResult(
    deadCodeReport: deadCodeReport,
    complexityReport: complexityReport,
    targetPath: './lib',
    duration: Duration(milliseconds: 100),
  );

  final reporter = JsonReporter();
  final json = await reporter.generate(result);
  print(json);
}
```

## License

MIT
