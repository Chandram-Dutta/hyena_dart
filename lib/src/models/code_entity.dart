/// The kind of Dart declaration a [CodeEntity] represents.
enum EntityType {
  /// A concrete (non-abstract) class.
  classDecl,

  /// An abstract class.
  abstractClass,

  /// A mixin declaration.
  mixin,

  /// An extension declaration.
  extension,

  /// An extension type declaration.
  extensionType,

  /// An enum declaration.
  enum_,

  /// A top-level or local function.
  function,

  /// A constructor of a class, enum or extension type.
  constructor,

  /// A method of a class, mixin, enum or extension.
  method,

  /// A getter, either top-level or a member.
  getter,

  /// A setter, either top-level or a member.
  setter,

  /// A top-level variable or constant.
  topLevelVariable,

  /// A field of a class, mixin, enum or extension type.
  field,

  /// A type alias.
  typedef,

  /// An import directive.
  import,

  /// A single value of an enum.
  enumValue,
}

/// A declaration discovered during dead code analysis.
///
/// Two entities are equal when they have the same [name], [type], [filePath]
/// and [parentName]; source position is not part of equality.
class CodeEntity {
  /// The simple name of the declaration, without any enclosing type.
  final String name;

  /// What kind of declaration this is.
  final EntityType type;

  /// Absolute path of the file that contains the declaration.
  final String filePath;

  /// 1-based line of the declaration's name.
  final int line;

  /// 1-based column of the declaration's name.
  final int column;

  /// Name of the enclosing type for members, or `null` for top-level
  /// declarations.
  final String? parentName;

  /// Whether the declaration's name is public (does not start with `_`).
  final bool isPublic;

  /// Whether the declaration is reachable through a public library export.
  final bool isExported;

  /// Creates a code entity.
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

  /// The qualified name: `Parent.name` for members, otherwise [name].
  String get fullName => parentName != null ? '$parentName.$name' : name;

  /// A human-readable label for [type], such as `abstract class` or `getter`.
  String get typeLabel => switch (type) {
    EntityType.classDecl => 'class',
    EntityType.abstractClass => 'abstract class',
    EntityType.mixin => 'mixin',
    EntityType.extension => 'extension',
    EntityType.extensionType => 'extension type',
    EntityType.enum_ => 'enum',
    EntityType.function => 'function',
    EntityType.constructor => 'constructor',
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
