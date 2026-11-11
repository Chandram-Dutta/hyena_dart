import 'package:analyzer/dart/element/element.dart';

/// Returns a stable identity for [element], built from its source path and
/// declaration offset, or `null` if it has no source.
String? elementKey(Element? element) {
  if (element == null) return null;
  final fragment = element.firstFragment;
  final source = fragment.libraryFragment?.source.fullName;
  if (source == null) return null;
  return '$source\u0000${fragment.offset}';
}
