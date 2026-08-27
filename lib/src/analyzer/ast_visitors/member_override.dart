import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

bool isOverridingMember(MethodDeclaration node) {
  if (_hasOverrideAnnotation(node)) return true;

  final element = node.declaredFragment?.element;
  final name = '${node.name.lexeme}${node.isSetter ? '=' : ''}';
  return element != null && _isOverridingExecutable(element, name);
}

bool isOverridingField(
  FieldDeclaration declaration,
  VariableDeclaration variable,
) {
  if (_hasOverrideAnnotation(declaration)) return true;

  final element = variable.declaredFragment?.element;
  if (element is! FieldElement) return false;
  final name = variable.name.lexeme;
  final getter = element.getter;
  final setter = element.setter;
  return (getter != null && _isOverridingExecutable(getter, name)) ||
      (setter != null && _isOverridingExecutable(setter, '$name='));
}

bool _hasOverrideAnnotation(AnnotatedNode node) =>
    node.metadata.any((annotation) => annotation.name.name == 'override');

bool _isOverridingExecutable(ExecutableElement element, String name) {
  final enclosing = element.enclosingElement;
  if (enclosing is! InterfaceElement) return false;
  final overridden = enclosing.getOverridden(
    Name.forLibrary(element.library, name),
  );
  return overridden != null && overridden.isNotEmpty;
}
