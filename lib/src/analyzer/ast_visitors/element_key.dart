import 'package:analyzer/dart/element/element.dart';

String? elementKey(Element? element) {
  if (element == null) return null;
  final fragment = element.firstFragment;
  final source = fragment.libraryFragment?.source.fullName;
  if (source == null) return null;
  return '$source\u0000${fragment.offset}';
}
