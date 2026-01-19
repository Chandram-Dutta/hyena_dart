import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references = {};
  final Set<String> typeReferences = {};
  final Set<String> imports = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    references.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    references.add(node.prefix.name);
    references.add(node.identifier.name);
    references.add('${node.prefix.name}.${node.identifier.name}');
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    typeReferences.add(node.name2.lexeme);
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
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    references.add(node.propertyName.name);
    super.visitPropertyAccess(node);
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
