import 'package:analyzer/dart/ast/ast.dart';

/// Offset of the token that names a constructor declaration.
///
/// Prefers the constructor name (`C.named`), then the enclosing type name
/// (`C()`), and falls back to the first token after metadata for the
/// `new`/`factory` declaration syntax that has no type name.
int constructorNameOffset(ConstructorDeclaration node) =>
    node.name?.offset ??
    node.typeName?.offset ??
    node.firstTokenAfterCommentAndMetadata.offset;
