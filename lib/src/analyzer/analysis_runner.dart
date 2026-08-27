import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/analyzer_config.dart';
import '../models/analysis_result.dart';
import '../models/dead_code_report.dart';
import 'complexity_analyzer.dart';
import 'dead_code_analyzer.dart';

typedef ConfigureAnalyzer = AnalyzerConfig Function(AnalyzerConfig config);

class AnalysisRunner {
  const AnalysisRunner();

  Future<AnalysisResult> analyze(
    String targetPath, {
    String? configPath,
    String? searchBoundary,
    bool includeDeadCode = true,
    bool includeComplexity = true,
    ConfigureAnalyzer? configure,
  }) async {
    final stopwatch = Stopwatch()..start();
    final workspace = await _Workspace.discover(targetPath);
    if (workspace == null) {
      final result = await _analyzePackage(
        targetPath: targetPath,
        configPath: configPath,
        searchBoundary: searchBoundary,
        includeDeadCode: includeDeadCode,
        includeComplexity: includeComplexity,
        configure: configure,
      );
      stopwatch.stop();
      return AnalysisResult(
        deadCodeReport: result.deadCodeReport,
        complexityReport: result.complexityReport,
        targetPath: targetPath,
        duration: stopwatch.elapsed,
      );
    }

    final packages =
        <
          ({
            _WorkspacePackage package,
            List<String> excludedPaths,
            AnalyzerConfig config,
          })
        >[];
    for (final package in workspace.packages) {
      final excludedPaths = workspace.packages
          .where(
            (candidate) =>
                candidate != package &&
                p.isWithin(package.rootPath, candidate.rootPath),
          )
          .map((candidate) => candidate.rootPath)
          .toList();
      var config = await AnalyzerConfig.load(
        configPath,
        targetPath: package.rootPath,
        searchBoundary:
            searchBoundary ?? (configPath == null ? workspace.rootPath : null),
      );
      if (configure != null) config = configure(config);
      packages.add((
        package: package,
        excludedPaths: excludedPaths,
        config: config,
      ));
    }

    List<DeadCodeReport?> deadCodeReports;
    List<Duration> deadCodeDurations;
    if (includeDeadCode) {
      final analyses = await DeadCodeAnalyzer.analyzeWorkspace([
        for (final input in packages)
          (
            targetPath: input.package.rootPath,
            config: input.config,
            excludedPaths: input.excludedPaths,
          ),
      ]);
      deadCodeReports = [for (final analysis in analyses) analysis.report];
      deadCodeDurations = [for (final analysis in analyses) analysis.duration];
    } else {
      deadCodeReports = List.filled(packages.length, null);
      deadCodeDurations = List.filled(packages.length, Duration.zero);
    }

    final packageResults = <AnalysisResult>[];
    for (var index = 0; index < packages.length; index++) {
      final input = packages[index];
      final complexityStopwatch = Stopwatch()..start();
      final complexityReport = includeComplexity
          ? await ComplexityAnalyzer(input.config).analyze(
              input.package.rootPath,
              excludedPaths: input.excludedPaths,
            )
          : null;
      complexityStopwatch.stop();
      packageResults.add(
        AnalysisResult(
          deadCodeReport: deadCodeReports[index],
          complexityReport: complexityReport,
          targetPath: input.package.rootPath,
          duration: deadCodeDurations[index] + complexityStopwatch.elapsed,
          packageName: input.package.name,
        ),
      );
    }
    stopwatch.stop();
    return AnalysisResult(
      targetPath: targetPath,
      duration: stopwatch.elapsed,
      packageResults: packageResults,
    );
  }

  Future<AnalysisResult> _analyzePackage({
    required String targetPath,
    String? packageName,
    List<String> excludedPaths = const [],
    String? configPath,
    String? searchBoundary,
    required bool includeDeadCode,
    required bool includeComplexity,
    ConfigureAnalyzer? configure,
  }) async {
    var config = await AnalyzerConfig.load(
      configPath,
      targetPath: targetPath,
      searchBoundary: searchBoundary,
    );
    if (configure != null) config = configure(config);
    final stopwatch = Stopwatch()..start();
    final deadCodeReport = includeDeadCode
        ? await DeadCodeAnalyzer(
            config,
          ).analyze(targetPath, excludedPaths: excludedPaths)
        : null;
    final complexityReport = includeComplexity
        ? await ComplexityAnalyzer(
            config,
          ).analyze(targetPath, excludedPaths: excludedPaths)
        : null;
    stopwatch.stop();
    return AnalysisResult(
      deadCodeReport: deadCodeReport,
      complexityReport: complexityReport,
      targetPath: targetPath,
      duration: stopwatch.elapsed,
      packageName: packageName,
    );
  }
}

class _Workspace {
  final String rootPath;
  final List<_WorkspacePackage> packages;

  const _Workspace(this.rootPath, this.packages);

  static Future<_Workspace?> discover(String targetPath) async {
    final absoluteTarget = p.normalize(p.absolute(targetPath));
    if (await FileSystemEntity.isFile(absoluteTarget)) return null;
    final target = Directory(absoluteTarget);
    if (!await target.exists()) return null;
    final pubspec = File(p.join(target.path, 'pubspec.yaml'));
    if (!await pubspec.exists()) return null;

    final rootYaml = _loadPubspec(pubspec);
    if (rootYaml['workspace'] == null) return null;

    final rootPath = p.normalize(await target.resolveSymbolicLinks());
    final packages = <_WorkspacePackage>[];
    final paths = <String>{};
    final names = <String>{};

    Future<void> visit(String packagePath, {YamlMap? parsed}) async {
      final normalizedPath = p.normalize(packagePath);
      if (!paths.add(normalizedPath)) {
        throw FormatException(
          'Workspace package is included more than once: $normalizedPath',
        );
      }
      final packagePubspec = File(p.join(normalizedPath, 'pubspec.yaml'));
      final yaml = parsed ?? _loadPubspec(packagePubspec);
      final name = yaml['name'];
      if (name is! String || name.isEmpty) {
        throw FormatException(
          'Workspace package $normalizedPath must declare a name.',
        );
      }
      if (!p.equals(normalizedPath, rootPath) &&
          yaml['resolution'] != 'workspace') {
        throw FormatException(
          'Workspace package $normalizedPath must declare '
          'resolution: workspace.',
        );
      }
      if (!names.add(name)) {
        throw FormatException('Workspace package name $name is duplicated.');
      }
      packages.add(_WorkspacePackage(name, normalizedPath));

      final entries = yaml['workspace'];
      if (entries == null) return;
      if (entries is! YamlList || entries.any((entry) => entry is! String)) {
        throw FormatException(
          'The workspace field in ${packagePubspec.path} must be a list of paths.',
        );
      }
      for (final entry in entries.cast<String>()) {
        final memberPaths = await _expandWorkspaceEntry(
          entry,
          packagePath: normalizedPath,
          workspaceRoot: rootPath,
        );
        for (final memberPath in memberPaths) {
          await visit(memberPath);
        }
      }
    }

    await visit(rootPath, parsed: rootYaml);
    packages.sort((left, right) {
      if (p.equals(left.rootPath, rootPath)) return -1;
      if (p.equals(right.rootPath, rootPath)) return 1;
      return left.rootPath.compareTo(right.rootPath);
    });
    return _Workspace(rootPath, packages);
  }

  static YamlMap _loadPubspec(File file) {
    if (!file.existsSync()) {
      throw FormatException('Workspace package is missing ${file.path}.');
    }
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) {
      throw FormatException('${file.path} must contain a YAML map.');
    }
    return yaml;
  }

  static Future<List<String>> _expandWorkspaceEntry(
    String entry, {
    required String packagePath,
    required String workspaceRoot,
  }) async {
    if (entry.isEmpty || p.isAbsolute(entry)) {
      throw FormatException('Workspace entries must be relative paths: $entry');
    }

    final matches = <String>[];
    if (_containsGlob(entry)) {
      await for (final entity in Glob(
        entry,
      ).list(root: packagePath, followLinks: false)) {
        if (entity is Directory &&
            await File(p.join(entity.path, 'pubspec.yaml')).exists()) {
          matches.add(entity.path);
        }
      }
    } else {
      matches.add(p.join(packagePath, entry));
    }
    if (matches.isEmpty) {
      throw FormatException('Workspace entry does not match a package: $entry');
    }

    final resolved = <String>[];
    for (final match in matches) {
      final directory = Directory(p.normalize(match));
      if (!await directory.exists() ||
          !await File(p.join(directory.path, 'pubspec.yaml')).exists()) {
        throw FormatException('Workspace package does not exist: $entry');
      }
      final memberPath = p.normalize(await directory.resolveSymbolicLinks());
      if (!p.isWithin(workspaceRoot, memberPath)) {
        throw FormatException(
          'Workspace package resolves outside the workspace root: $entry',
        );
      }
      resolved.add(memberPath);
    }
    resolved.sort();
    return resolved;
  }

  static bool _containsGlob(String value) =>
      value.contains('*') ||
      value.contains('?') ||
      value.contains('[') ||
      value.contains('{');
}

class _WorkspacePackage {
  final String name;
  final String rootPath;

  const _WorkspacePackage(this.name, this.rootPath);
}
