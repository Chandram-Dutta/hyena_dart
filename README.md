# Hyena Dart

<img src="https://raw.githubusercontent.com/Chandram-Dutta/hyena_dart/main/hyena_dart_logo.png" width="200" alt="Hyena Logo">


A powerful Flutter/Dart codebase analyzer that detects dead code and calculates code complexity metrics. Built using the official Dart `analyzer` package for accurate AST-based analysis.

## Features

- **Dead Code Detection** - Find unused classes, constructors, functions, methods, enums, variables, fields, and typedefs
- **Complexity Metrics** - Cyclomatic complexity, lines of code, nesting levels, parameter count, maintainability index
- **Multiple Output Formats** - Console (colored), JSON, Markdown, HTML, and SARIF 2.1
- **Configurable** - Exclude patterns, thresholds, and analysis options via YAML config
- **CI/CD Ready** - Finding-based exit codes, baselines, source suppressions, and SARIF output

## Installation

Install the CLI from pub.dev:

```bash
dart pub global activate hyena_dart
hyena_dart --help
```

Or add Hyena to a project as a dev dependency:

```bash
dart pub add --dev hyena_dart
dart run hyena_dart analyze .
```

## Quick Start

```bash
# Analyze current directory
hyena_dart analyze .

# Analyze specific path
hyena_dart analyze lib

# Dead code analysis only
hyena_dart dead-code lib

# Complexity analysis only
hyena_dart complexity lib
```

## CLI Reference

### Commands

#### `analyze` - Full Analysis
Run both dead code and complexity analysis.

```bash
hyena_dart analyze <path> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | `-f` | Output format: `console`, `json`, `markdown`, `html`, `sarif` | `console` |
| `--output` | `-o` | Output file path (prints to stdout if not specified) | - |
| `--config` | `-c` | Path to configuration file | - |
| `--no-color` | - | Disable colored output | `false` |
| `--baseline` | - | Suppress findings recorded in a baseline file | - |
| `--write-baseline` | - | Write current findings to a baseline file | - |
| `--fail-on` | - | Exit 1 for `dead-code`, `complexity`, or both | - |
| `--dead-code` | - | Include dead code analysis | `true` |
| `--complexity` | - | Include complexity analysis | `true` |

**Examples:**
```bash
# Full analysis with HTML report
hyena_dart analyze lib --format=html --output=report.html

# JSON output for CI/CD
hyena_dart analyze lib --format=json --output=analysis.json

# Skip complexity analysis
hyena_dart analyze lib --no-complexity
```

#### `dead-code` - Dead Code Analysis
Analyze codebase for unused code entities.

```bash
hyena_dart dead-code <path> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | `-f` | Output format | `console` |
| `--output` | `-o` | Output file path | - |
| `--config` | `-c` | Path to configuration file | - |
| `--baseline` | - | Suppress findings recorded in a baseline file | - |
| `--write-baseline` | - | Write current findings to a baseline file | - |
| `--fail-on` | - | Exit 1 when dead-code findings remain | - |
| `--ignore-exports` | - | Ignore exported entities | `true` |
| `--ignore-private` | - | Ignore private entities | `false` |

**Examples:**
```bash
# Find all unused code including exports
hyena_dart dead-code lib --no-ignore-exports

# Markdown report
hyena_dart dead-code lib --format=markdown --output=dead-code.md
```

#### `complexity` - Complexity Analysis
Analyze code complexity metrics.

```bash
hyena_dart complexity <path> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | `-f` | Output format | `console` |
| `--output` | `-o` | Output file path | - |
| `--config` | `-c` | Path to configuration file | - |
| `--baseline` | - | Suppress findings recorded in a baseline file | - |
| `--write-baseline` | - | Write current findings to a baseline file | - |
| `--fail-on` | - | Exit 1 when complexity findings remain | - |
| `--threshold` | `-t` | Cyclomatic complexity threshold for warnings | `20` |

**Examples:**
```bash
# Set custom threshold
hyena_dart complexity lib --threshold=15

# JSON output
hyena_dart complexity lib --format=json
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

### SARIF
SARIF 2.1 output for code-scanning systems:

```bash
hyena_dart analyze . --format=sarif --output=hyena.sarif
```

## CI/CD Usage

Hyena exits with code 0 by default, even when it reports findings. Opt into a
stable exit code 1 for selected categories:

```bash
hyena_dart analyze . --fail-on=dead-code,complexity
```

To adopt Hyena without failing on existing findings, create and commit a
baseline, then fail only on new findings:

```bash
hyena_dart analyze . --write-baseline=hyena-baseline.json
hyena_dart analyze . \
  --baseline=hyena-baseline.json \
  --fail-on=dead-code,complexity
```

Baseline fingerprints use the rule, package-relative path, symbol type, and
full symbol name. Moving a declaration to another line does not invalidate its
baseline entry.

## Source Suppressions

Place an ignore comment immediately before a declaration when a finding is
intentional:

```dart
// hyena:ignore dead-code
void retainedForReflection() {}

// hyena:ignore complexity
void generatedDispatcher() {
  // All complexity threshold findings are suppressed.
}

// Rule-specific complexity suppressions:
// hyena:ignore cyclomatic-complexity
void stateMachine() {}

// hyena:ignore max-nesting
void nestedParser() {}

// hyena:ignore max-parameters
void frameworkCallback(int a, int b, int c, int d, int e, int f, int g) {}
```

Suppressed dead-code declarations remain reachability roots, so dependencies
used by an intentionally retained declaration are not reported as cascading
dead code.

## Metrics Explained

### Dead Code Detection
Detects the following unused entities:
- Classes (including abstract classes)
- Explicit unnamed, named, and private constructors
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

## Releasing

Releases tagged as `vX.Y.Z` are verified and published to pub.dev through
GitHub Actions using short-lived OIDC credentials. The tag version must match
the `version` in `pubspec.yaml`.

Before using the workflow for the first time, configure the package's
**Automated publishing** settings at
[`pub.dev/packages/hyena_dart/admin`](https://pub.dev/packages/hyena_dart/admin):

- Repository: `Chandram-Dutta/hyena_dart`
- Tag pattern: `v{{version}}`
- Required GitHub Actions environment: `pub.dev`

Then bump `pubspec.yaml`, update `CHANGELOG.md`, merge those changes to `main`,
and create a matching GitHub release. The publishing workflow runs formatting,
analysis, and tests before the official Dart publishing workflow uploads the
package.

## License

MIT
