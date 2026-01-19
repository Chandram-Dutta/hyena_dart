import 'package:hyena_dart/hyena_dart.dart';
import 'package:test/test.dart';

void main() {
  group('AnalyzerConfig', () {
    test('creates default config', () {
      final config = AnalyzerConfig();
      expect(config.cyclomaticThreshold, 20);
      expect(config.maxNestingLevel, 5);
      expect(config.ignoreExports, true);
    });

    test('copyWith preserves values', () {
      final config = AnalyzerConfig(cyclomaticThreshold: 15);
      final copied = config.copyWith(maxNestingLevel: 3);
      expect(copied.cyclomaticThreshold, 15);
      expect(copied.maxNestingLevel, 3);
    });
  });

  group('CodeEntity', () {
    test('fullName includes parent', () {
      final entity = CodeEntity(
        name: 'method',
        type: EntityType.method,
        filePath: 'test.dart',
        line: 1,
        column: 0,
        parentName: 'MyClass',
        isPublic: true,
      );
      expect(entity.fullName, 'MyClass.method');
    });

    test('typeLabel returns correct label', () {
      final entity = CodeEntity(
        name: 'MyClass',
        type: EntityType.classDecl,
        filePath: 'test.dart',
        line: 1,
        column: 0,
        isPublic: true,
      );
      expect(entity.typeLabel, 'class');
    });
  });
}
