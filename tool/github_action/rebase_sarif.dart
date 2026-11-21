// Rewrites the relative finding URIs in a Hyena SARIF report so they are
// relative to the repository root, which GitHub code scanning expects.
//
// Usage: dart rebase_sarif.dart <sarif-file> <analysis-target> <repo-root>
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart rebase_sarif.dart <sarif-file> <analysis-target> <repo-root>',
    );
    exitCode = 64;
    return;
  }
  final [sarifPath, target, repoRoot] = args;
  final prefix = _relativeSegments(
    _analysisRoot(target),
    Directory(repoRoot).resolveSymbolicLinksSync(),
  );
  if (prefix == null) {
    stderr.writeln('Warning: $target is outside $repoRoot; paths left as is.');
    return;
  }
  if (prefix.isEmpty) return;

  final file = File(sarifPath);
  final sarif = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  for (final run in sarif['runs'] as List) {
    final entries = [
      ...(run as Map)['results'] as List? ?? const [],
      for (final invocation in run['invocations'] as List? ?? const [])
        ...(invocation as Map)['toolExecutionNotifications'] as List? ??
            const [],
    ];
    for (final result in entries) {
      for (final location
          in (result as Map)['locations'] as List? ?? const []) {
        final artifact =
            (location as Map)['physicalLocation']?['artifactLocation'];
        if (artifact is! Map || artifact['uri'] is! String) continue;
        final uri = Uri.parse(artifact['uri'] as String);
        if (uri.hasScheme || uri.path.startsWith('/')) continue;
        artifact['uri'] = uri
            .replace(pathSegments: [...prefix, ...uri.pathSegments])
            .toString();
      }
    }
  }
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sarif));
}

/// The nearest directory at or above [target] with a `pubspec.yaml`, or the
/// target's own directory; the same root Hyena reports paths against.
String _analysisRoot(String target) {
  var directory = FileSystemEntity.isFileSync(target)
      ? File(target).absolute.parent
      : Directory(target).absolute;
  directory = Directory(directory.resolveSymbolicLinksSync());
  final fallback = directory;
  while (true) {
    if (File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    ).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return fallback.path;
    directory = parent;
  }
}

/// Path segments of [path] below [root], or `null` when it is not inside.
List<String>? _relativeSegments(String path, String root) {
  List<String> segments(String value) => Uri.directory(
    value,
    windows: Platform.isWindows,
  ).pathSegments.where((segment) => segment.isNotEmpty).toList();
  final pathSegments = segments(path);
  final rootSegments = segments(root);
  if (pathSegments.length < rootSegments.length) return null;
  for (var i = 0; i < rootSegments.length; i++) {
    final a = pathSegments[i], b = rootSegments[i];
    final same = Platform.isWindows
        ? a.toLowerCase() == b.toLowerCase()
        : a == b;
    if (!same) return null;
  }
  return pathSegments.sublist(rootSegments.length);
}
