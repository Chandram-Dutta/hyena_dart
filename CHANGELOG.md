## [1.0.0] - 2026-01-19

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
