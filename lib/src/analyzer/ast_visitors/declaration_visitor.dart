import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/source/line_info.dart';

import '../../models/code_entity.dart';

class DeclarationVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final LineInfo lineInfo;
  final Set<String> exportedNames;
  final bool ignoreMain;
  final List<CodeEntity> declarations = [];
  final Map<int, CodeEntity> elementIdToEntity = {};
  String? _currentClass;

  DeclarationVisitor(
    this.filePath,
    this.lineInfo, {
    this.exportedNames = const {},
    this.ignoreMain = true,
  });

  bool _isPublic(String name) => !name.startsWith('_');

  CodeEntity _entity({
    required String name,
    required EntityType type,
    required int offset,
    required bool isPublic,
    String? parentName,
    bool isExported = false,
  }) {
    final location = lineInfo.getLocation(offset);
    return CodeEntity(
      name: name,
      type: type,
      filePath: filePath,
      line: location.lineNumber,
      column: location.columnNumber,
      parentName: parentName,
      isPublic: isPublic,
      isExported: isExported,
    );
  }

  void _record(CodeEntity entity, Element2? element) {
    declarations.add(entity);
    if (element != null) {
      elementIdToEntity[element.id] = entity;
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.name.lexeme;
    _record(
      _entity(
        name: name,
        type: node.abstractKeyword != null
            ? EntityType.abstractClass
            : EntityType.classDecl,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );
    _currentClass = name;
    super.visitClassDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final name = node.name.lexeme;
    _record(
      _entity(
        name: name,
        type: EntityType.mixin,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );
    _currentClass = name;
    super.visitMixinDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final name = node.name?.lexeme;
    if (name != null) {
      _record(
        _entity(
          name: name,
          type: EntityType.extension,
          offset: node.name!.offset,
          isPublic: _isPublic(name),
          isExported: exportedNames.contains(name),
        ),
        node.declaredFragment?.element,
      );
    }
    _currentClass = name;
    super.visitExtensionDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    final name = node.name.lexeme;
    _record(
      _entity(
        name: name,
        type: EntityType.extensionType,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );
    _currentClass = name;
    super.visitExtensionTypeDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final name = node.name.lexeme;
    _record(
      _entity(
        name: name,
        type: EntityType.enum_,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );

    _currentClass = name;
    for (final constant in node.constants) {
      _record(
        _entity(
          name: constant.name.lexeme,
          type: EntityType.enumValue,
          offset: constant.name.offset,
          parentName: name,
          isPublic: true,
        ),
        constant.declaredFragment?.element,
      );
    }
    super.visitEnumDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (ignoreMain && name == 'main') {
      super.visitFunctionDeclaration(node);
      return;
    }

    EntityType type;
    if (node.isGetter) {
      type = EntityType.getter;
    } else if (node.isSetter) {
      type = EntityType.setter;
    } else {
      type = EntityType.function;
    }

    _record(
      _entity(
        name: name,
        type: type,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (_isOverride(node)) {
      super.visitMethodDeclaration(node);
      return;
    }

    EntityType type;
    if (node.isGetter) {
      type = EntityType.getter;
    } else if (node.isSetter) {
      type = EntityType.setter;
    } else {
      type = EntityType.method;
    }

    _record(
      _entity(
        name: name,
        type: type,
        offset: node.name.offset,
        parentName: _currentClass,
        isPublic: _isPublic(name),
      ),
      node.declaredFragment?.element,
    );
    super.visitMethodDeclaration(node);
  }

  bool _isOverride(MethodDeclaration node) {
    for (final annotation in node.metadata) {
      if (annotation.name.name == 'override') {
        return true;
      }
    }
    return false;
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final name = variable.name.lexeme;
      _record(
        _entity(
          name: name,
          type: EntityType.topLevelVariable,
          offset: variable.name.offset,
          isPublic: _isPublic(name),
          isExported: exportedNames.contains(name),
        ),
        variable.declaredFragment?.element,
      );
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final variable in node.fields.variables) {
      final name = variable.name.lexeme;
      _record(
        _entity(
          name: name,
          type: EntityType.field,
          offset: variable.name.offset,
          parentName: _currentClass,
          isPublic: _isPublic(name),
        ),
        variable.declaredFragment?.element,
      );
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    final name = node.name.lexeme;
    _record(
      _entity(
        name: name,
        type: EntityType.typedef,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );
    super.visitFunctionTypeAlias(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    final name = node.name.lexeme;
    _record(
      _entity(
        name: name,
        type: EntityType.typedef,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: exportedNames.contains(name),
      ),
      node.declaredFragment?.element,
    );
    super.visitGenericTypeAlias(node);
  }
}
