import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element2.dart';

bool isOverridingMember(MethodDeclaration node) {
  if (node.metadata.any((annotation) => annotation.name.name == 'override')) {
    return true;
  }

  final element = node.declaredFragment?.element;
  final enclosing = element?.enclosingElement2;
  if (enclosing is! InterfaceElement2) return false;

  final name = '${node.name.lexeme}${node.isSetter ? '=' : ''}';
  final overridden = enclosing.getOverridden(
    Name.forLibrary(element?.library2, name),
  );
  return overridden != null && overridden.isNotEmpty;
}
