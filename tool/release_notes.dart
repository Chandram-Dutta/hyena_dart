import 'dart:io';

/// Returns the body of the `## [version]` section in [changelog], or `null`
/// when that section is missing or contains only whitespace.
String? extractReleaseNotes(String changelog, String version) {
  final heading = '## [$version]';
  final lines = changelog.split(RegExp(r'\r?\n'));
  final start = lines.indexWhere((line) => line.startsWith(heading));
  if (start == -1) return null;
  final body = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## [')) break;
    body.add(line);
  }
  final notes = body.join('\n').trim();
  return notes.isEmpty ? null : notes;
}

/// Prints the CHANGELOG.md release notes for `version`, failing when the
/// `## [version]` section is missing or empty.
///
/// Usage: `dart run tool/release_notes.dart <version> [changelog-path]`
void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/release_notes.dart <version> [changelog-path]',
    );
    exitCode = 64;
    return;
  }
  final version = args[0];
  final path = args.length > 1 ? args[1] : 'CHANGELOG.md';
  final notes = extractReleaseNotes(File(path).readAsStringSync(), version);
  if (notes == null) {
    stderr.writeln('No release notes in $path under "## [$version]".');
    exitCode = 1;
    return;
  }
  stdout.writeln(notes);
}
