enum EntityType {
  classDecl,
  abstractClass,
  mixin,
  extension,
  extensionType,
  enum_,
  function,
  method,
  getter,
  setter,
  topLevelVariable,
  field,
  typedef,
  import,
  enumValue,
}

class CodeEntity {
  final String name;
  final EntityType type;
  final String filePath;
  final int line;
  final int column;
  final String? parentName;
  final bool isPublic;
  final bool isExported;

  CodeEntity({
    required this.name,
    required this.type,
    required this.filePath,
    required this.line,
    required this.column,
    this.parentName,
    required this.isPublic,
    this.isExported = false,
  });

  String get fullName => parentName != null ? '$parentName.$name' : name;

  String get typeLabel => switch (type) {
    EntityType.classDecl => 'class',
    EntityType.abstractClass => 'abstract class',
    EntityType.mixin => 'mixin',
    EntityType.extension => 'extension',
    EntityType.extensionType => 'extension type',
    EntityType.enum_ => 'enum',
    EntityType.function => 'function',
    EntityType.method => 'method',
    EntityType.getter => 'getter',
    EntityType.setter => 'setter',
    EntityType.topLevelVariable => 'variable',
    EntityType.field => 'field',
    EntityType.typedef => 'typedef',
    EntityType.import => 'import',
    EntityType.enumValue => 'enum value',
  };

  @override
  String toString() => '$typeLabel $fullName at $filePath:$line:$column';

  @override
  bool operator ==(Object other) =>
      other is CodeEntity &&
      name == other.name &&
      type == other.type &&
      filePath == other.filePath &&
      parentName == other.parentName;

  @override
  int get hashCode => Object.hash(name, type, filePath, parentName);
}
