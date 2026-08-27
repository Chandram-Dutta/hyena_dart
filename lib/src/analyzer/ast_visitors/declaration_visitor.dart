import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/source/line_info.dart';

import '../../models/code_entity.dart';
import '../source_suppression.dart';
import 'element_key.dart';
import 'member_override.dart';

class DeclarationVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final LineInfo lineInfo;
  final Set<String> exportedNames;
  final Set<String> liveNames;
  final bool ignoreMain;
  final Set<String> entryPoints;
  final Set<String> entryPointAnnotations;
  final List<CodeEntity> declarations = [];
  final Map<String, CodeEntity> elementKeyToEntity = {};
  final Set<String> liveElementKeys = {};
  String? _currentClass;
  String? _currentContainerElementKey;
  bool _currentContainerExported = false;
  bool _currentContainerLive = false;

  DeclarationVisitor(
    this.filePath,
    this.lineInfo, {
    this.exportedNames = const {},
    this.liveNames = const {},
    this.ignoreMain = true,
    Iterable<String> entryPoints = const [],
    Iterable<String> entryPointAnnotations = const [],
  }) : entryPoints = entryPoints.map((name) => name.trim()).toSet(),
       entryPointAnnotations = entryPointAnnotations
           .map(_normalizeAnnotationName)
           .toSet();

  bool _isPublic(String name) => !name.startsWith('_');

  bool _ignoresDeadCode(AstNode node) =>
      hyenaIgnoredRules(node).contains('dead-code');

  static String _normalizeAnnotationName(String name) {
    final trimmed = name.trim();
    return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  }

  bool _isConfiguredEntryPoint(String name, {String? parentName}) {
    if (entryPoints.contains(name)) return true;
    return parentName != null && entryPoints.contains('$parentName.$name');
  }

  bool _hasEntryPointAnnotation(AnnotatedNode node) {
    return node.metadata.any((annotation) {
      final fullName = annotation.name.toSource();
      final shortName = fullName.split('.').last;
      return entryPointAnnotations.any(
        (configured) => configured.contains('.')
            ? configured == fullName
            : configured == shortName,
      );
    });
  }

  bool _isLiveDeclaration(
    String name,
    AnnotatedNode node, {
    String? parentName,
  }) =>
      _isConfiguredEntryPoint(name, parentName: parentName) ||
      _hasEntryPointAnnotation(node);

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
    final key = elementKey(element);
    if (key != null) {
      elementKeyToEntity[key] = entity;
      if (isLive) {
        liveElementKeys.add(key);
        final containerKey = _currentContainerElementKey;
        if (entity.parentName != null && containerKey != null) {
          liveElementKeys.add(containerKey);
        }
      }
    }
  }

  void _visitContainer(
    String? name,
    String? elementKey,
    bool isExported,
    bool isLive,
    void Function() visit,
  ) {
    final previousClass = _currentClass;
    final previousElementKey = _currentContainerElementKey;
    final previousExported = _currentContainerExported;
    final previousLive = _currentContainerLive;
    _currentClass = name;
    _currentContainerElementKey = elementKey;
    _currentContainerExported = isExported;
    _currentContainerLive = isLive;
    visit();
    _currentClass = previousClass;
    _currentContainerElementKey = previousElementKey;
    _currentContainerExported = previousExported;
    _currentContainerLive = previousLive;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name) || _isLiveDeclaration(name, node);
    final isIgnored = _ignoresDeadCode(node);
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
      isLive: isLive || isIgnored,
    );
    _visitContainer(
      name,
      elementKey(node.declaredFragment?.element),
      isExported,
      isLive || isIgnored,
      () => super.visitClassDeclaration(node),
    );
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name) || _isLiveDeclaration(name, node);
    final isIgnored = _ignoresDeadCode(node);
    _record(
      _entity(
        name: name,
        type: EntityType.mixin,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive || isIgnored,
    );
    _visitContainer(
      name,
      elementKey(node.declaredFragment?.element),
      isExported,
      isLive || isIgnored,
      () => super.visitMixinDeclaration(node),
    );
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final name = node.name?.lexeme;
    final isExported = name != null && exportedNames.contains(name);
    final isLive = name == null
        ? _hasEntryPointAnnotation(node)
        : liveNames.contains(name) || _isLiveDeclaration(name, node);
    final isIgnored = _ignoresDeadCode(node);
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
        isLive: isLive || isIgnored,
      );
    }
    _visitContainer(
      name,
      elementKey(node.declaredFragment?.element),
      isExported,
      isLive || isIgnored,
      () => super.visitExtensionDeclaration(node),
    );
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name) || _isLiveDeclaration(name, node);
    final isIgnored = _ignoresDeadCode(node);
    _record(
      _entity(
        name: name,
        type: EntityType.extensionType,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive || isIgnored,
    );
    _visitContainer(
      name,
      elementKey(node.declaredFragment?.element),
      isExported,
      isLive || isIgnored,
      () => super.visitExtensionTypeDeclaration(node),
    );
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final name = node.name.lexeme;
    final isExported = exportedNames.contains(name);
    final isLive = liveNames.contains(name) || _isLiveDeclaration(name, node);
    final isIgnored = _ignoresDeadCode(node);
    _record(
      _entity(
        name: name,
        type: EntityType.enum_,
        offset: node.name.offset,
        isPublic: _isPublic(name),
        isExported: isExported,
      ),
      node.declaredFragment?.element,
      isLive: isLive || isIgnored,
    );

    _visitContainer(
      name,
      elementKey(node.declaredFragment?.element),
      isExported,
      isLive || isIgnored,
      () {
        for (final constant in node.constants) {
          final constantName = constant.name.lexeme;
          _record(
            _entity(
              name: constantName,
              type: EntityType.enumValue,
              offset: constant.name.offset,
              parentName: name,
              isPublic: true,
              isExported: isExported,
            ),
            constant.declaredFragment?.element,
            isLive:
                isLive ||
                _isLiveDeclaration(constantName, constant, parentName: name) ||
                _ignoresDeadCode(constant),
          );
        }
        super.visitEnumDeclaration(node);
      },
    );
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
      isLive:
          liveNames.contains(name) ||
          _isLiveDeclaration(name, node) ||
          _ignoresDeadCode(node),
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
      isLive:
          (_currentContainerLive && _isPublic(name)) ||
          _isLiveDeclaration(name, node, parentName: _currentClass) ||
          _ignoresDeadCode(node),
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final name = node.name?.lexeme ?? 'new';
    final isPublic = _isPublic(name);
    _record(
      _entity(
        name: name,
        type: EntityType.constructor,
        offset: node.name?.offset ?? node.returnType.offset,
        parentName: _currentClass,
        isPublic: isPublic,
        isExported: _currentContainerExported && isPublic,
      ),
      node.declaredFragment?.element,
      isLive:
          (_currentContainerLive && isPublic) ||
          _isLiveDeclaration(name, node, parentName: _currentClass) ||
          _ignoresDeadCode(node),
    );
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
        isLive:
            liveNames.contains(name) ||
            _isLiveDeclaration(name, node) ||
            _ignoresDeadCode(node),
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
        isLive:
            (_currentContainerLive && _isPublic(name)) ||
            _isLiveDeclaration(name, node, parentName: _currentClass) ||
            _ignoresDeadCode(node),
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
      isLive:
          liveNames.contains(name) ||
          _isLiveDeclaration(name, node) ||
          _ignoresDeadCode(node),
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
      isLive:
          liveNames.contains(name) ||
          _isLiveDeclaration(name, node) ||
          _ignoresDeadCode(node),
    );
    super.visitGenericTypeAlias(node);
  }
}
