import 'analysis_path.dart';

/// A Dart file that an analyzer could not analyze and left out of its report.
///
/// Analyzers record skipped files instead of aborting the whole run so that
/// one broken, unresolvable, or unreadable file does not hide results for the
/// rest of the target.
class SkippedFile {
  /// Absolute path of the skipped file.
  final String filePath;

  /// Human-readable, single-line explanation of why the file was skipped.
  final String reason;

  /// Creates a record that [filePath] was skipped because of [reason].
  const SkippedFile({required this.filePath, required this.reason});

  /// Serializes this entry to JSON.
  ///
  /// When [rootPath] is given, [filePath] is emitted relative to it.
  Map<String, dynamic> toJson({String? rootPath}) => {
    'filePath': rootPath == null
        ? filePath
        : relativeAnalysisPath(filePath, rootPath),
    'reason': reason,
  };

  @override
  String toString() => 'SkippedFile($filePath: $reason)';
}

/// Collapses [message] onto a single line so it is safe to show in reports.
String singleLineReason(Object message) =>
    message.toString().replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();
