# Contributing to Hyena Dart

Thanks for helping improve Hyena Dart.

## Development setup

Use Dart 3.10.3 or newer, then run:

```bash
dart pub get
dart run bin/hyena_dart.dart --help
```

Before submitting a pull request, run the same core checks as CI:

```bash
dart run tool/check_version.dart
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Add regression tests for behavior changes. Analyzer changes should use the
smallest representative Dart fixture, and reporter changes should update the
relevant golden only when the output change is intentional.

## Issues and pull requests

Search existing issues before opening a new one. Bug reports should include the
Hyena version, Dart version, operating system, command, minimal reproduction,
and actual output. Pull requests should stay focused and explain user-visible
behavior changes and verification performed.

Do not include credentials, proprietary source, or other sensitive data in
issues, reports, fixtures, or logs. Report vulnerabilities privately as
described in [SECURITY.md](SECURITY.md).

Releases are maintained by the repository owner. Do not publish packages or
create release tags as part of a contribution.
