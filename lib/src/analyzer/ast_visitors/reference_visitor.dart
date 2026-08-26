import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';

class ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references = {};
  final Set<String> typeReferences = {};
  final Set<String> imports = {};
  final Set<int> referencedElementIds = {};
  final Map<int, Set<int>> referenceGraph = {};
  final Set<int> rootElementIds = {};
  int? _currentDeclarationId;

  void _visitInScope(
    Element2? element,
    void Function() visit, {
    bool isRoot = false,
  }) {
    final previousDeclarationId = _currentDeclarationId;
    if (element != null) {
      _currentDeclarationId = element.id;
      if (isRoot) rootElementIds.add(element.id);
    }
    visit();
    _currentDeclarationId = previousDeclarationId;
  }

  bool _isOverride(MethodDeclaration node) =>
      node.metadata.any((annotation) => annotation.name.name == 'override');

  void _recordElement(Element2? element) {
    if (element == null) return;
    _recordElementIdAndExtension(element);
    if (element is PropertyAccessorElement2) {
      final variable = element.variable3;
      if (variable != null) _recordElementIdAndExtension(variable);
    }
  }

  void _recordElementIdAndExtension(Element2 element) {
    _recordElementId(element.id);
    final enclosing = element.enclosingElement2;
    if (enclosing is ExtensionElement2) {
      _recordElementId(enclosing.id);
    } else if (enclosing is ExtensionTypeElement2) {
      _recordElementId(enclosing.id);
    }
  }

  void _recordElementId(int elementId) {
    referencedElementIds.add(elementId);
    final sourceId = _currentDeclarationId;
    if (sourceId == null) {
      rootElementIds.add(elementId);
    } else {
      referenceGraph.putIfAbsent(sourceId, () => {}).add(elementId);
    }
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
      isRoot: _isOverride(node),
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
    if (element is FieldElement2 || element is TopLevelVariableElement2) {
      _visitInScope(element, () => super.visitVariableDeclaration(node));
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
