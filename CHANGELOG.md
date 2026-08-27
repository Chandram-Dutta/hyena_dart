## Unreleased

## [1.2.1] - 2026-08-27

### Added
- Add a Flutter-style workspace fixture plus Windows-native path, recursive glob, symlink-alias, and malformed-workspace regressions
- Add normalized golden compatibility coverage for console, JSON, Markdown, HTML, and SARIF reports

### Fixed
- Preserve resolved dead-code reachability across workspace package boundaries without conflating same-named declarations or references from unreachable callers

## [1.2.0] - 2026-08-27

### Added
- Add `--version` to both executables and enforce runtime/package version consistency in CI and publishing
- Analyze Dart workspaces package by package with nested/glob discovery, per-package configuration, package-scoped reports, and workspace-relative findings
- Add configurable dead-code entry points and entry-point annotations for routes, generated callbacks, serializers, dependency injection, and plugin registrations

### Fixed
- Keep workspace members out of parent scans so files are not double-counted or analyzed with the wrong package configuration
- Preserve baselines, SARIF locations, and MCP summaries across package-scoped workspace results

## [1.1.2] - 2026-08-27

### Added
- Add a stdio-only, workspace-confined MCP server with one read-only analysis tool
- Add a repository-local agent skill for safe Hyena MCP and JSON CLI workflows

## [1.1.1] - 2026-08-27

### Fixed
- Correct the minimum `analyzer` and `glob` constraints so supported lower-bound dependency resolution compiles and runs

### CI
- Validate lower dependency bounds with static analysis and an end-to-end CLI smoke test

## [1.1.0] - 2026-08-27

### Added
- Analyze individual Dart files as well as directories
- Detect unused explicit constructors
- Support `hyena:ignore` source suppressions for dead code and individual complexity rules
- Add versioned finding baselines with stable, line-independent fingerprints
- Add opt-in `--fail-on` exit codes for dead-code and complexity findings
- Add SARIF 2.1 output for code-scanning integrations

### Fixed
- Preserve public APIs from directly importable package libraries and library parts
- Follow every conditional import and export branch
- Recognize inherited member implementations without requiring an `@override` annotation
- Conservatively retain unresolved dynamic member targets

## [1.0.1] - 2026-08-27

### Fixed
- Honor configured complexity thresholds, dead-code settings, and target-project configuration without CLI defaults overriding YAML
- Detect dead code through declaration reachability, including exported APIs, extensions, extension types, and their dependencies
- Respect barrel export visibility and `show`/`hide` combinators
- Report accurate one-based source locations and physical line totals
- Analyze constructors, closures, modern control flow, and constructor initializer lists in their correct complexity scopes
- Exclude nested closure bodies from outer-function metrics
- Calculate token-based Halstead volume and a normalized maintainability index
- Surface parse and resolution failures instead of silently omitting source files
- Escape source-controlled content in HTML reports

## [1.0.0] - 2026-05-23

### Added
- Initial release of Hyena Dart codebase analyzer
- Dead code detection for unused classes, functions, methods, enums, variables, fields, and typedefs
- Code complexity metrics including cyclomatic complexity, lines of code, nesting levels, parameter count, and maintainability index
- Multiple output formats: Console (colored), JSON, Markdown, and HTML
- CLI tool with three main commands: `analyze`, `dead-code`, and `complexity`
- Configuration file support via `hyena.yaml` or `analysis_options.yaml`
- Configurable exclusion patterns for generated files (.g.dart, .freezed.dart, etc.)
- Comprehensive documentation and CLI reference
- Unit tests for core models and configuration
- AST-based analysis using Dart's official analyzer package
- Export tracking for dead code detection accuracy
- Progress indicators and detailed reporting
- MIT License
