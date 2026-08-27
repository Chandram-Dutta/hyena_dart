import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'element_key.dart';
import 'member_override.dart';

class ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references = {};
  final Set<String> typeReferences = {};
  final Set<String> imports = {};
  final Set<String> unresolvedMemberNames = {};
  final Map<String, Set<String>> referenceGraph = {};
  final Set<String> rootElementKeys = {};
  String? _currentDeclarationKey;

  void _visitInScope(
    Element? element,
    void Function() visit, {
    bool isRoot = false,
  }) {
    final previousDeclarationKey = _currentDeclarationKey;
    final key = elementKey(element);
    if (key != null) {
      _currentDeclarationKey = key;
      if (isRoot) rootElementKeys.add(key);
    }
    visit();
    _currentDeclarationKey = previousDeclarationKey;
  }

  void _recordElement(Element? element) {
    if (element == null) return;
    _recordElementAndExtension(element);
    if (element is PropertyAccessorElement) {
      _recordElementAndExtension(element.variable);
    }
  }

  void _recordElementAndExtension(Element element) {
    _recordElementKey(elementKey(element));
    final enclosing = element.enclosingElement;
    if (enclosing is ExtensionElement) {
      _recordElementKey(elementKey(enclosing));
    } else if (enclosing is ExtensionTypeElement) {
      _recordElementKey(elementKey(enclosing));
    }
  }

  void _recordElementKey(String? key) {
    if (key == null) return;
    final sourceKey = _currentDeclarationKey;
    if (sourceKey == null) {
      rootElementKeys.add(key);
    } else {
      referenceGraph.putIfAbsent(sourceKey, () => {}).add(key);
    }
  }

  bool _isResolvedByCompoundParent(Expression node) {
    final parent = node.parent;
    if (parent is AssignmentExpression &&
        identical(parent.leftHandSide, node)) {
      return parent.readElement != null || parent.writeElement != null;
    }
    if (parent is PrefixExpression && identical(parent.operand, node)) {
      return parent.readElement != null || parent.writeElement != null;
    }
    if (parent is PostfixExpression && identical(parent.operand, node)) {
      return parent.readElement != null || parent.writeElement != null;
    }
    return false;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitClassDeclaration(node),
    );
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitMixinDeclaration(node),
    );
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitExtensionDeclaration(node),
    );
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitExtensionTypeDeclaration(node),
    );
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitEnumDeclaration(node),
    );
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitEnumConstantDeclaration(node),
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitFunctionDeclaration(node),
      isRoot: node.name.lexeme == 'main',
    );
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitMethodDeclaration(node),
      isRoot: isOverridingMember(node),
    );
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitConstructorDeclaration(node),
    );
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    final first = node.variables.variables.firstOrNull;
    _visitInScope(
      first?.declaredFragment?.element,
      () => super.visitTopLevelVariableDeclaration(node),
    );
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final first = node.fields.variables.firstOrNull;
    _visitInScope(
      first?.declaredFragment?.element,
      () => super.visitFieldDeclaration(node),
    );
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element is FieldElement || element is TopLevelVariableElement) {
      final declaration = node.parent?.parent;
      _visitInScope(
        element,
        () => super.visitVariableDeclaration(node),
        isRoot:
            declaration is FieldDeclaration &&
            isOverridingField(declaration, node),
      );
    } else {
      super.visitVariableDeclaration(node);
    }
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitFunctionTypeAlias(node),
    );
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _visitInScope(
      node.declaredFragment?.element,
      () => super.visitGenericTypeAlias(node),
    );
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
    if (node.identifier.element == null &&
        node.prefix.element != null &&
        !_isResolvedByCompoundParent(node)) {
      unresolvedMemberNames.add(node.identifier.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    typeReferences.add(node.name.lexeme);
    _recordElement(node.element);
    super.visitNamedType(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    final typeName = node.type.name.lexeme;
    typeReferences.add(typeName);
    references.add(typeName);
    if (node.name != null) {
      references.add('$typeName.${node.name!.name}');
    }
    _recordElement(node.element);
    _recordElement(node.type.element);
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
    if (node.methodName.element == null) {
      unresolvedMemberNames.add(node.methodName.name);
    }
    _recordElement(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    references.add(node.propertyName.name);
    if (node.propertyName.element == null &&
        !_isResolvedByCompoundParent(node)) {
      unresolvedMemberNames.add(node.propertyName.name);
    }
    _recordElement(node.propertyName.element);
    super.visitPropertyAccess(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _recordElement(node.readElement);
    _recordElement(node.writeElement);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _recordElement(node.readElement);
    _recordElement(node.writeElement);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _recordElement(node.readElement);
    _recordElement(node.writeElement);
    super.visitPrefixExpression(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      imports.add(uri);
    }
  }

  @override
  void visitExportDirective(ExportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      imports.add(uri);
    }
  }

  @override
  void visitAnnotation(Annotation node) {
    references.add(node.name.name);
    super.visitAnnotation(node);
  }

  @override
  void visitExtendsClause(ExtendsClause node) {
    typeReferences.add(node.superclass.name.lexeme);
    super.visitExtendsClause(node);
  }

  @override
  void visitImplementsClause(ImplementsClause node) {
    for (final interface in node.interfaces) {
      typeReferences.add(interface.name.lexeme);
    }
    super.visitImplementsClause(node);
  }

  @override
  void visitWithClause(WithClause node) {
    for (final mixin in node.mixinTypes) {
      typeReferences.add(mixin.name.lexeme);
    }
    super.visitWithClause(node);
  }

  @override
  void visitMixinOnClause(MixinOnClause node) {
    for (final constraint in node.superclassConstraints) {
      typeReferences.add(constraint.name.lexeme);
    }
    super.visitMixinOnClause(node);
  }

  Set<String> get allReferences => {...references, ...typeReferences};
}
