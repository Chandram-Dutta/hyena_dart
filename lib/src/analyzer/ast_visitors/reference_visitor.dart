import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';

class ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references = {};
  final Set<String> typeReferences = {};
  final Set<String> imports = {};
  final Set<int> referencedElementIds = {};

  void _recordElement(Element2? element) {
    if (element == null) return;
    referencedElementIds.add(element.id);
    if (element is PropertyAccessorElement2) {
      final variable = element.variable3;
      if (variable != null) referencedElementIds.add(variable.id);
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    references.add(node.name);
    _recordElement(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    references.add(node.prefix.name);
    references.add(node.identifier.name);
    references.add('${node.prefix.name}.${node.identifier.name}');
    _recordElement(node.prefix.element);
    _recordElement(node.identifier.element);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    typeReferences.add(node.name2.lexeme);
    _recordElement(node.element2);
    super.visitNamedType(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    final typeName = node.type.name2.lexeme;
    typeReferences.add(typeName);
    references.add(typeName);
    if (node.name != null) {
      references.add('$typeName.${node.name!.name}');
    }
    _recordElement(node.element);
    _recordElement(node.type.element2);
    super.visitConstructorName(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target != null) {
      if (node.target is SimpleIdentifier) {
        final targetName = (node.target as SimpleIdentifier).name;
        references.add(targetName);
        references.add('$targetName.${node.methodName.name}');
      }
    }
    references.add(node.methodName.name);
    _recordElement(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    references.add(node.propertyName.name);
    _recordElement(node.propertyName.element);
    super.visitPropertyAccess(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _recordElement(node.readElement2);
    _recordElement(node.writeElement2);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _recordElement(node.readElement2);
    _recordElement(node.writeElement2);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _recordElement(node.readElement2);
    _recordElement(node.writeElement2);
    super.visitPrefixExpression(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      imports.add(uri);
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      imports.add(uri);
    }
    super.visitExportDirective(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    references.add(node.name.name);
    super.visitAnnotation(node);
  }

  @override
  void visitExtendsClause(ExtendsClause node) {
    typeReferences.add(node.superclass.name2.lexeme);
    super.visitExtendsClause(node);
  }

  @override
  void visitImplementsClause(ImplementsClause node) {
    for (final interface in node.interfaces) {
      typeReferences.add(interface.name2.lexeme);
    }
    super.visitImplementsClause(node);
  }

  @override
  void visitWithClause(WithClause node) {
    for (final mixin in node.mixinTypes) {
      typeReferences.add(mixin.name2.lexeme);
    }
    super.visitWithClause(node);
  }

  @override
  void visitMixinOnClause(MixinOnClause node) {
    for (final constraint in node.superclassConstraints) {
      typeReferences.add(constraint.name2.lexeme);
    }
    super.visitMixinOnClause(node);
  }

  Set<String> get allReferences => {...references, ...typeReferences};
}
