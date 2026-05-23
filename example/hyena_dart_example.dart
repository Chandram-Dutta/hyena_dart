import 'package:hyena_dart/hyena_dart.dart';

Future<void> main(List<String> args) async {
  final targetPath = args.isNotEmpty ? args.first : 'lib';
  final config = AnalyzerConfig(cyclomaticThreshold: 15);

  final deadCode = await DeadCodeAnalyzer(config).analyze(targetPath);
  print(
    'Unused entities: ${deadCode.unusedCount} / ${deadCode.totalDeclarations}',
  );
  for (final entity in deadCode.unusedEntities.take(10)) {
    print('  - ${entity.typeLabel} ${entity.fullName} (${entity.filePath})');
  }

  final complexity = await ComplexityAnalyzer(config).analyze(targetPath);
  print(
    'High-complexity functions: ${complexity.highComplexityFunctions.length}',
  );
}
