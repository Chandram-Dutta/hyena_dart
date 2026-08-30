import 'dart:convert';
import 'dart:io';

import 'package:hyena_dart/src/analyzer/source_file_filter.dart';
import 'package:path/path.dart' as p;

class BenchmarkCorpus {
  final String id;
  final String kind;
  final String targetPath;
  final int dartFiles;
  final int sourceLines;
  final int sourceBytes;
  final int? packageCount;
  final bool generated;

  const BenchmarkCorpus({
    required this.id,
    required this.kind,
    required this.targetPath,
    required this.dartFiles,
    required this.sourceLines,
    required this.sourceBytes,
    required this.packageCount,
    required this.generated,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'dartFiles': dartFiles,
    'sourceLines': sourceLines,
    'sourceBytes': sourceBytes,
    if (packageCount != null) 'packageCount': packageCount,
    'generated': generated,
  };

  static Future<BenchmarkCorpus> inspectExternal(
    String targetPath, {
    required String label,
  }) async {
    final target = Directory(p.normalize(p.absolute(targetPath)));
    if (!await target.exists()) {
      throw ArgumentError('Benchmark target does not exist: $targetPath');
    }

    var dartFiles = 0;
    var sourceLines = 0;
    var sourceBytes = 0;
    await for (final entity in target.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.relative(entity.path, from: target.path);
      if (isDefaultExcludedSourcePath(relative)) continue;
      final content = await entity.readAsString();
      dartFiles++;
      sourceLines += const LineSplitter().convert(content).length;
      sourceBytes += utf8.encode(content).length;
    }
    if (dartFiles == 0) {
      throw ArgumentError('Benchmark target contains no Dart files.');
    }

    return BenchmarkCorpus(
      id: label,
      kind: 'external',
      targetPath: p.normalize(await target.resolveSymbolicLinks()),
      dartFiles: dartFiles,
      sourceLines: sourceLines,
      sourceBytes: sourceBytes,
      packageCount: null,
      generated: false,
    );
  }
}

class BenchmarkCorpusGenerator {
  final Directory rootDirectory;

  const BenchmarkCorpusGenerator(this.rootDirectory);

  Future<BenchmarkCorpus> singlePackage({
    required String id,
    required int fileCount,
  }) async {
    if (fileCount < 1) throw ArgumentError.value(fileCount, 'fileCount');
    final root = Directory(p.join(rootDirectory.path, id));
    await root.create(recursive: true);
    final stats = _SourceStats();

    await _writeText(p.join(root.path, 'pubspec.yaml'), '''
name: $id
environment:
  sdk: ^3.10.0
''');
    await _writeText(p.join(root.path, 'hyena.yaml'), '''
hyena:
  dead_code:
    ignore_main: true
    ignore_exports: true
    ignore_private: false
''');

    for (var index = 0; index < fileCount; index++) {
      final next = index + 1 < fileCount ? index + 1 : null;
      await _writeDart(
        p.join(root.path, 'lib', 'src', _unitFile(index)),
        _singleUnit(index, next),
        stats,
      );
    }
    await _writeDart(p.join(root.path, 'bin', 'main.dart'), '''
import '../lib/src/${_unitFile(0)}';

void main() {
  print(live0000(1));
}
''', stats);

    return BenchmarkCorpus(
      id: id,
      kind: 'single-package',
      targetPath: root.path,
      dartFiles: stats.files,
      sourceLines: stats.lines,
      sourceBytes: stats.bytes,
      packageCount: 1,
      generated: true,
    );
  }

  Future<BenchmarkCorpus> workspace({
    required String id,
    required int packages,
    required int filesPerPackage,
  }) async {
    if (packages < 2) throw ArgumentError.value(packages, 'packages');
    if (filesPerPackage < 1) {
      throw ArgumentError.value(filesPerPackage, 'filesPerPackage');
    }
    final root = Directory(p.join(rootDirectory.path, id));
    await root.create(recursive: true);
    final stats = _SourceStats();
    final packageNames = [
      for (var index = 0; index < packages; index++) _packageName(index),
    ];

    await _writeText(p.join(root.path, 'pubspec.yaml'), '''
name: benchmark_workspace
environment:
  sdk: ^3.10.0
workspace:
  - packages/*
''');
    await _writeText(p.join(root.path, 'hyena.yaml'), '''
hyena:
  dead_code:
    ignore_main: true
    ignore_exports: true
    ignore_private: false
''');

    for (var packageIndex = 0; packageIndex < packages; packageIndex++) {
      final packageName = packageNames[packageIndex];
      final packageRoot = p.join(
        root.path,
        'packages',
        _packageDirectory(packageIndex),
      );
      final nextDependency = packageIndex + 1 < packages
          ? '''
dependencies:
  ${packageNames[packageIndex + 1]}: any
'''
          : '';
      await _writeText(p.join(packageRoot, 'pubspec.yaml'), '''
name: $packageName
resolution: workspace
environment:
  sdk: ^3.10.0
$nextDependency''');

      for (var fileIndex = 0; fileIndex < filesPerPackage; fileIndex++) {
        final nextFile = fileIndex + 1 < filesPerPackage ? fileIndex + 1 : null;
        final nextPackage = nextFile == null && packageIndex + 1 < packages
            ? packageIndex + 1
            : null;
        await _writeDart(
          p.join(packageRoot, 'lib', 'src', _unitFile(fileIndex)),
          _workspaceUnit(
            packageIndex: packageIndex,
            fileIndex: fileIndex,
            nextFile: nextFile,
            nextPackage: nextPackage,
            nextPackageName: nextPackage == null
                ? null
                : packageNames[nextPackage],
          ),
          stats,
        );
      }

      if (packageIndex == 0) {
        await _writeDart(p.join(packageRoot, 'bin', 'main.dart'), '''
import '../lib/src/${_unitFile(0)}';

void invokeDynamic(dynamic target) {
  target.activate();
}

void main() {
  final collision = DynamicCollision();
  invokeDynamic(collision);
  print(liveP00F0000(1) + SharedName().value());
}
''', stats);
      }
    }

    await _writePackageConfig(root, packageNames);
    return BenchmarkCorpus(
      id: id,
      kind: 'workspace',
      targetPath: root.path,
      dartFiles: stats.files,
      sourceLines: stats.lines,
      sourceBytes: stats.bytes,
      packageCount: packages + 1,
      generated: true,
    );
  }

  Future<void> _writePackageConfig(
    Directory root,
    List<String> packageNames,
  ) async {
    final packages = <Map<String, Object?>>[
      {
        'name': 'benchmark_workspace',
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.10',
      },
      for (var index = 0; index < packageNames.length; index++)
        {
          'name': packageNames[index],
          'rootUri': '../packages/${_packageDirectory(index)}',
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
    ];
    await _writeText(
      p.join(root.path, '.dart_tool', 'package_config.json'),
      '${const JsonEncoder.withIndent('  ').convert({'configVersion': 2, 'packages': packages})}\n',
    );
  }
}

String _singleUnit(int index, int? next) {
  final currentName = _indexName(index);
  final nextName = next == null ? null : _indexName(next);
  final import = next == null ? '' : "import '${_unitFile(next)}';\n\n";
  final liveNext = nextName == null ? 'value + 1' : 'live$nextName(value + 1)';
  final deadNext = nextName == null ? 'value - 1' : 'dead$nextName(value - 1)';
  return '''
${import}class LiveNode$currentName {
  const LiveNode$currentName();

  int run(int value) {
    if (value.isEven) {
      return $liveNext;
    }
    for (var index = 0; index < 2; index++) {
      value += index;
    }
    return $liveNext;
  }
}

int live$currentName(int value) => LiveNode$currentName().run(value);

class DeadNode$currentName {
  const DeadNode$currentName();

  int run(int value) => $deadNext;
}

int dead$currentName(int value) => DeadNode$currentName().run(value);
''';
}

String _workspaceUnit({
  required int packageIndex,
  required int fileIndex,
  required int? nextFile,
  required int? nextPackage,
  required String? nextPackageName,
}) {
  final packageName = packageIndex.toString().padLeft(2, '0');
  final fileName = _indexName(fileIndex);
  late final String import;
  late final String liveNext;
  late final String deadNext;
  if (nextFile != null) {
    final nextName = _indexName(nextFile);
    import = "import '${_unitFile(nextFile)}';\n\n";
    liveNext = 'liveP${packageName}F$nextName(value + 1)';
    deadNext = 'deadP${packageName}F$nextName(value - 1)';
  } else if (nextPackage != null && nextPackageName != null) {
    final nextIndex = nextPackage.toString().padLeft(2, '0');
    import = "import 'package:$nextPackageName/src/${_unitFile(0)}';\n\n";
    liveNext = 'liveP${nextIndex}F0000(value + 1)';
    deadNext = 'deadP${nextIndex}F0000(value - 1)';
  } else {
    import = '';
    liveNext = 'value + 1';
    deadNext = 'value - 1';
  }
  final collisions = fileIndex == 0
      ? '''
class SharedName {
  const SharedName();

  int value() => $packageIndex;
}

class DynamicCollision {
  const DynamicCollision();

  void activate() {}
}

'''
      : '';
  return '''
$import${collisions}class LiveP${packageName}F$fileName {
  const LiveP${packageName}F$fileName();

  int run(int value) {
    if (value.isEven) {
      return $liveNext;
    }
    for (var index = 0; index < 2; index++) {
      value += index;
    }
    return $liveNext;
  }
}

int liveP${packageName}F$fileName(int value) =>
    LiveP${packageName}F$fileName().run(value);

class DeadP${packageName}F$fileName {
  const DeadP${packageName}F$fileName();

  int run(int value) => $deadNext;
}

int deadP${packageName}F$fileName(int value) =>
    DeadP${packageName}F$fileName().run(value);
''';
}

String _indexName(int index) => index.toString().padLeft(4, '0');

String _unitFile(int index) => 'unit_${_indexName(index)}.dart';

String _packageDirectory(int index) =>
    'package_${index.toString().padLeft(2, '0')}';

String _packageName(int index) => switch (index) {
  0 => 'benchmark_app',
  1 => 'design_system',
  2 => 'shared_core',
  _ => 'feature_${index.toString().padLeft(2, '0')}',
};

Future<void> _writeDart(String path, String content, _SourceStats stats) async {
  await _writeText(path, content);
  stats.files++;
  stats.lines += const LineSplitter().convert(content).length;
  stats.bytes += utf8.encode(content).length;
}

Future<void> _writeText(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

class _SourceStats {
  int files = 0;
  int lines = 0;
  int bytes = 0;
}
