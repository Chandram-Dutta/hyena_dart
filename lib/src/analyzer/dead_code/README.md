# Dead-code analysis internals

`DeadCodeAnalyzer` coordinates two phases: collect symbols for each package,
then compute reachability across all collected packages. Its public API remains
in `../dead_code_analyzer.dart`.

- `../source_discovery.dart` enumerates Dart sources and applies the shared
  exclusion policy used by dead-code and complexity analysis. Callers normalize
  and sort paths and restrict them to their analyzer contexts.
- `symbol_collector.dart` resolves every included source unit and runs the
  declaration and reference visitors. Resolution errors abort collection rather
  than producing an incomplete report.
- `library_names.dart` computes public library names, export combinators, parts,
  and conditional import roots using package-resolution metadata.
- `symbols.dart` carries the per-package declarations, graph, roots, fallback
  references, configuration, and collection duration.
- `reachability.dart` merges package graphs, applies each package's root policy,
  traverses live references, and builds one report per input package.

Keep symbol collection independent of report construction. In a workspace,
reachability must run after every package has been collected so cross-package
references remain visible. Retain the name-based fallback for declarations
without element keys and the conservative roots for unresolved member calls.
These components are internal and are not exported from `lib/hyena_dart.dart`.
