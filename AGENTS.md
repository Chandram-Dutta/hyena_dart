## Project summary

Hyena Dart is a Dart package + CLI that analyzes Dart/Flutter codebases for:

- Dead code (unused declarations)
- Complexity metrics (cyclomatic complexity, nesting, LOC, maintainability index)

Primary entrypoints:

- CLI: `bin/hyena_dart.dart` (runs `HyenaCommandRunner`)
- Library exports: `lib/hyena_dart.dart`

Source layout:

- `lib/src/analyzer/` - AST-based analyzers and visitors
- `lib/src/cli/` - CLI command runner and commands
- `lib/src/config/` - config parsing and defaults
- `lib/src/models/` - report/result models
- `lib/src/reporters/` - console/json/markdown/html output

---

## Quick start (from a fresh clone)

```bash
dart pub get
dart run bin/hyena_dart.dart --help
```

Run analysis:

```bash
# Full analysis (dead code + complexity)
dart run bin/hyena_dart.dart analyze .

# Dead code only
dart run bin/hyena_dart.dart dead-code lib

# Complexity only
dart run bin/hyena_dart.dart complexity lib
```

---

## Common development commands

### Format

```bash
dart format .
```

### Static analysis (lint/type checks)

```bash
dart analyze
```

Notes:

- Lints are configured in `analysis_options.yaml` (includes `package:lints/recommended.yaml`).
- Dart is statically typed; type issues surface via `dart analyze`.

### Tests

```bash
dart test
```

---

## How the tool works (high level)

### Dead code analysis

Typical flow:

1. Parse Dart sources with the official `analyzer` package.
2. Visit declarations (classes, methods, functions, variables, etc.).
3. Visit references/usages.
4. Compute unused entities based on declarations minus reachable references, with config-driven exceptions.

Look in:

- `lib/src/analyzer/dead_code_analyzer.dart`
- `lib/src/analyzer/ast_visitors/declaration_visitor.dart`
- `lib/src/analyzer/ast_visitors/reference_visitor.dart`

### Complexity analysis

1. Parse Dart sources.
2. Visit functions/method bodies.
3. Compute per-function metrics (cyclomatic complexity, nesting, LOC, etc.).

Look in:

- `lib/src/analyzer/complexity_analyzer.dart`
- `lib/src/analyzer/ast_visitors/complexity_visitor.dart`

### Reporting

Reporters take an `AnalysisResult` and render to a target format.

- `lib/src/reporters/reporter.dart` - base interface
- `console_reporter.dart`, `json_reporter.dart`, `markdown_reporter.dart`, `html_reporter.dart`

---

## Configuration

Hyena reads configuration from either:

- `hyena.yaml` (preferred when analyzing another repo)
- `analysis_options.yaml` under a `hyena:` key (when integrating into a project)

Config model:

- `lib/src/config/analyzer_config.dart`

When editing config behavior:

- Keep defaults conservative.
- Add new config fields in a backward-compatible way (new optional fields with defaults).

---

## Conventions for contributions

- Keep code in `lib/src/...`; only export stable surfaces from `lib/hyena_dart.dart`.
- Prefer pure functions / small methods in analyzers and visitors; avoid deeply nested logic.
- Avoid printing directly from analyzers; send data to reporters.
- Keep CLI parsing in `lib/src/cli/` and analysis logic in `lib/src/analyzer/`.

### Adding a new CLI option

Typical steps:

1. Update the command definition in `lib/src/cli/cli_runner.dart`.
2. Thread the option into `AnalyzerConfig`.
3. Update analyzers/reporters to respect the new config field.
4. Add/adjust tests under `test/`.

---

## Testing guidance

Current tests are unit tests in `test/`.

When adding new behavior:

- Add a unit test for the new config/model logic.
- For analyzer changes, prefer fixture-based tests:
  - Create a small temporary Dart project structure under `test/fixtures/...`.
  - Run analyzers against that fixture directory and assert the report contents.

---

## Release process (manual today)

This repository currently has no release automation. Versioning is controlled via:

- `pubspec.yaml` version
- `CHANGELOG.md`

---

## Troubleshooting

### `dart analyze` fails with SDK constraint errors

- Ensure you are using Dart SDK `^3.10.3` (see `pubspec.yaml`).

### Analyzer can’t resolve imports in a target repo

- Ensure the target path is a Dart package (has `pubspec.yaml`) or is within a package workspace.
- Run `dart pub get` in the target repo before analyzing.
