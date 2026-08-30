import 'package:hyena_dart/hyena_dart.dart';

Future<void> main(List<String> args) async {
  final targetPath = args.isNotEmpty ? args.first : 'lib';
  final config = AnalyzerConfig(cyclomaticThreshold: 15);
  final reportRoot = analysisRootForTarget(targetPath);

  final deadCode = await DeadCodeAnalyzer(config).analyze(targetPath);
  print(
    'Unused entities: ${deadCode.unusedCount} / ${deadCode.totalDeclarations}',
  );
  for (final entity in deadCode.unusedEntities.take(10)) {
    final path = relativeAnalysisPath(entity.filePath, reportRoot);
    print('  - ${entity.typeLabel} ${entity.fullName} ($path)');
  }

  final complexity = await ComplexityAnalyzer(config).analyze(targetPath);
  print(
    'High-complexity functions: ${complexity.highComplexityFunctions.length}',
  );
}
