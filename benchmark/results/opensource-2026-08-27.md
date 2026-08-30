# Hyena Dart open-source production benchmark

Date: 2026-08-27

These measurements use the pre-release v1.2.2 Hyena working tree based on
v1.2.1. They include the benchmark harness and analyzer 8.4 compatibility fixes;
they are not measurements of the unmodified pub.dev v1.2.1 package.

## Method

- Linux x64 orb, 2 logical CPUs
- Flutter 3.44.9 / Dart 3.12.2 (`6b182d2c7585eba26d4edce0f97630effd256c33`)
- Public repositories cloned at the exact commits below
- One unmeasured warm-up followed by three measured samples, run sequentially
- Dependency resolution prepared before measurement
- Benchmark target mode did not run target code, invoke dependency setup, or
  write inside the target during measurement
- Generated, `.dart_tool`, and `build` artifacts excluded

## Results

| Repository and commit | Checks | Dart files | Source lines | Median | p95 | Files/s | RSS growth | Result signature |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| [invertase/melos `a793a409`](https://github.com/invertase/melos/commit/a793a409ef0ad23e6ac31207ca7f2ec3faebd619) | Both | 110 | 33,193 | 7.533 s | 8.550 s | 14.6 | 25.0 MiB | 1,320 declarations; 66 dead-code candidates; 36 complexity violations |
| [flame-engine/flame `b4578fc6`](https://github.com/flame-engine/flame/commit/b4578fc6a4f4087463cedf485f1a7079f9369b2e) | Complexity | 1,625 | 165,415 | 1.460 s | 1.814 s | 1,113.3 | 7.6 MiB | 13,890 functions; 190 threshold violations |
| [flutter/packages `bd3cbc1b`](https://github.com/flutter/packages/commit/bd3cbc1b8c3f44daf36eb8c455255e0f626223eb) | Complexity | 3,514 | 1,535,690 | 8.354 s | 8.416 s | 420.6 | 21.5 MiB | 101,719 functions; 3,297 threshold violations |

The structured benchmark JSON, including every sample, runtime metadata, and
correctness signatures, was retained during release verification but is not
included in this repository. This report is the durable public summary.

## Production usefulness

The output found concrete review leads in mature projects:

- Melos: [`_VersionMixin._version`](https://github.com/invertase/melos/blob/a793a409ef0ad23e6ac31207ca7f2ec3faebd619/packages/melos/lib/src/commands/version.dart#L80)
  measured cyclomatic complexity 47, 296 LOC, and 20 parameters.
- Flame: [`_Lexer.isUnicodeIdentifierStart`](https://github.com/flame-engine/flame/blob/b4578fc6a4f4087463cedf485f1a7079f9369b2e/packages/flame_jenny/jenny/lib/src/parse/tokenize.dart#L1097)
  measured cyclomatic complexity 56; several parser and component paths also
  reached nesting depth 8–9.
- Flutter packages: [`_tokenize`](https://github.com/flutter/packages/blob/bd3cbc1b8c3f44daf36eb8c455255e0f626223eb/packages/rfw/lib/src/dart/text.dart#L815)
  measured cyclomatic complexity 785 across 1,224 LOC. The scan also highlighted
  deeply nested generator paths and very wide API/copy constructors.

These are triage candidates, not automatic refactoring instructions. Generated
localization code, intentionally table-driven lexers, public API compatibility,
framework entry points, and tests can all justify high metrics or apparent dead
code. A maintainer should configure exclusions/entry points and review source
context before changing anything.

## Compatibility findings

The production runs found and drove fixes for three real issues:

1. Hyena's analyzer dependency could not parse current Dart dot-shorthand
   syntax.
2. Non-error dartdoc directives incorrectly aborted complexity analysis.
3. `.dart_tool`/`build` artifacts and inherited field implementations produced
   invalid input or false dead-code candidates.

Version 1.2.2 fixes those cases and regression-tests them. On Melos, the
inherited-field fix reduced dead-code candidates from 93 to 66.

One boundary remains: fully resolved dead-code analysis of current Dart 3.12
private named parameters requires migration to analyzer 12's new element/AST
APIs. Flame therefore has a valid complexity benchmark but no dead-code timing;
silently excluding the failing sources would have produced a misleading result.
`flutter/packages` has no root Dart workspace declaration, so its repository-wide
complexity scan is represented as one analysis tree.

## Internal regression comparison

Repeated three-sample quick comparisons varied enough that no release-level
speedup or regression claim is justified: one run had seven lower medians and
two higher medians, while a later run had lower medians across every comparable
case. The later run also exposed a volatile timestamp in the JSON reporter's
correctness hash; v1.2.2 now uses stable semantic summaries for reporter
correctness and refuses comparisons when corpus metadata or correctness
signatures differ. Results remain advisory until repeated hosted-runner
measurements establish a stable history.
