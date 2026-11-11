import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'element_key.dart';

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

/// Element keys of every inherited member that a member declared in [unit]
/// overrides.
Set<String> overriddenMemberKeys(CompilationUnit unit) {
  final collector = _OverriddenMemberCollector();
  unit.accept(collector);
  return collector.keys;
}

class _OverriddenMemberCollector extends RecursiveAstVisitor<void> {
  final Set<String> keys = {};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) {
      _addOverridden(element, '${node.name.lexeme}${node.isSetter ? '=' : ''}');
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final variable in node.fields.variables) {
      final element = variable.declaredFragment?.element;
      if (element is! FieldElement) continue;
      final name = variable.name.lexeme;
      final getter = element.getter;
      final setter = element.setter;
      if (getter != null) _addOverridden(getter, name);
      if (setter != null) _addOverridden(setter, '$name=');
    }
    super.visitFieldDeclaration(node);
  }

  void _addOverridden(ExecutableElement element, String name) {
    final enclosing = element.enclosingElement;
    if (enclosing is! InterfaceElement) return;
    final overridden = enclosing.getOverridden(
      Name.forLibrary(element.library, name),
    );
    for (final member in overridden ?? const <ExecutableElement>[]) {
      _addKey(elementKey(member));
      if (member is PropertyAccessorElement) {
        _addKey(elementKey(member.variable));
      }
    }
  }

  void _addKey(String? key) {
    if (key != null) keys.add(key);
  }
}
