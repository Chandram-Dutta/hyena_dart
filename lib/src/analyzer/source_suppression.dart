import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Returns the rule ids listed in `// hyena:ignore rule-a, rule-b` comments
/// directly before [node].
Set<String> hyenaIgnoredRules(AstNode node) {
  final rules = <String>{};
  Token? comment = node.beginToken.precedingComments;
  while (comment != null) {
    final match = RegExp(
      r'hyena:ignore\s+([a-z0-9-]+(?:\s*,\s*[a-z0-9-]+)*)',
    ).firstMatch(comment.lexeme);
    if (match != null) {
      rules.addAll(match.group(1)!.split(',').map((rule) => rule.trim()));
    }
    comment = comment.next;
  }
  return rules;
}
