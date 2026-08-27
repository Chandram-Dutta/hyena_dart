import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/source/line_info.dart';

import '../../models/code_entity.dart';
import 'member_override.dart';

class DeclarationVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final LineInfo lineInfo;
  final Set<String> exportedNames;
  final Set<String> liveNames;
  final bool ignoreMain;
  final List<CodeEntity> declarations = [];
  final Map<int, CodeEntity> elementIdToEntity = {};
  final Set<int> exportedElementIds = {};
  final Set<int> liveElementIds = {};
  String? _currentClass;
  bool _currentContainerExported = false;
  bool _currentContainerLive = false;

  DeclarationVisitor(
    this.filePath,
    this.lineInfo, {
    this.exportedNames = const {},
    this.liveNames = const {},
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

  void _record(CodeEntity entity, Element2? element, {bool isLive = false}) {
    declarations.add(entity);
    if (element != null) {
      elementIdToEntity[element.id] = entity;
      if (entity.isExported) exportedElementIds.add(element.id);
      if (isLive) liveElementIds.add(element.id);
    }
  }

  void _visitContainer(
    String? name,
    bool isExported,
    bool isLive,
    void Function() visit,
  ) {
    final previousClass = _currentClass;
    final previousExported = _currentContainerExported;
    final previousLive = _currentContainerLive;
    _currentClass = name;
    _currentContainerExported = isExported;
    _currentContainerLive = isLive;
    visit();
    _currentClass = previousClass;
    _currentContainerExported = previousExported;
    _currentContainerLive = previousLive;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name);
    _record(
      _entity(
        name: name,
        type: node.abstractKeyword != null
            ? EntityType.abstractClass
            : EntityType.classDecl,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive,
    );
    _visitContainer(
      name,
      isExported,
      isLive,
      () => super.visitClassDeclaration(node),
    );
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name);
    _record(
      _entity(
        name: name,
        type: EntityType.mixin,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive,
    );
    _visitContainer(
      name,
      isExported,
      isLive,
      () => super.visitMixinDeclaration(node),
    );
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final name = node.name?.lexeme;
    final isExported = name != null && exportedNames.contains(name);
    final isLive = name != null && liveNames.contains(name);
    if (name != null) {
      _record(
        _entity(
          name: name,
          type: EntityType.extension,
          offset: node.name!.offset,
          isPublic: _isPublic(name),
          isExported: isExported,
        ),
        node.declaredFragment?.element,
        isLive: isLive,
      );
    }
    _visitContainer(
      name,
      isExported,
      isLive,
      () => super.visitExtensionDeclaration(node),
    );
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name);
    _record(
      _entity(
        name: name,
        type: EntityType.extensionType,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive,
    );
    _visitContainer(
      name,
      isExported,
      isLive,
      () => super.visitExtensionTypeDeclaration(node),
    );
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name);
    _record(
      _entity(
        name: name,
        type: EntityType.enum_,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive,
    );

    _visitContainer(name, isExported, isLive, () {
      for (final constant in node.constants) {
        _record(
          _entity(
            name: constant.name.lexeme,
            type: EntityType.enumValue,
            offset: constant.name.offset,
            parentName: name,
            isPublic: true,
            isExported: isExported,
          ),
          constant.declaredFragment?.element,
          isLive: isLive,
        );
      }
      super.visitEnumDeclaration(node);
    });
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
      isLive: liveNames.contains(name),
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (isOverridingMember(node)) {
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
        isExported: _currentContainerExported && _isPublic(name),
      ),
      node.declaredFragment?.element,
      isLive: _currentContainerLive && _isPublic(name),
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final name = node.name?.lexeme;
    final isPublic = name == null || _isPublic(name);
    final element = node.declaredFragment?.element;
    if (_currentContainerExported && isPublic && element != null) {
      exportedElementIds.add(element.id);
    }
    if (_currentContainerLive && isPublic && element != null) {
      liveElementIds.add(element.id);
    }
    super.visitConstructorDeclaration(node);
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
        isLive: liveNames.contains(name),
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
          isExported: _currentContainerExported && _isPublic(name),
        ),
        variable.declaredFragment?.element,
        isLive: _currentContainerLive && _isPublic(name),
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
      isLive: liveNames.contains(name),
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
      isLive: liveNames.contains(name),
    );
    super.visitGenericTypeAlias(node);
  }
}
