import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:hyena_dart/hyena_dart.dart';
import 'package:hyena_dart/src/mcp/mcp_analysis_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MCP analysis safety', () {
    test('returns bounded structured findings with relative paths', () async {
      final project = await _createProject();
      addTearDown(() => project.delete(recursive: true));
      final service = await McpAnalysisService.create(
        project.path,
        limits: const McpAnalysisLimits(maxFindings: 1),
      );

      final result = await service.analyze(
        targetPath: 'lib',
        checks: 'complexity',
      );

      expect(result['target'], 'lib');
      expect(result['checks'], 'complexity');
      final summary = result['summary'] as Map<String, Object?>;
      expect(summary['totalFindings'], greaterThan(1));
      expect(summary['returnedFindings'], 1);
      expect(summary['truncated'], isTrue);
      final finding = (result['findings'] as List).single as Map;
      expect(finding['path'], 'lib/example.dart');
      expect(jsonEncode(result), isNot(contains(project.path)));
    });

    test('enforces source file limits before analysis', () async {
      final project = await _createProject();
      addTearDown(() => project.delete(recursive: true));
      final service = await McpAnalysisService.create(
        project.path,
        limits: const McpAnalysisLimits(maxDartFiles: 0),
      );

      await expectLater(
        service.analyze(targetPath: 'lib', checks: 'complexity'),
        throwsA(
          isA<McpAnalysisException>().having(
            (error) => error.message,
            'message',
            contains('file safety limit'),
          ),
        ),
      );
    });

    test('cancels an active request and releases the service', () async {
      final project = await _createProject();
      addTearDown(() => project.delete(recursive: true));
      final service = await McpAnalysisService.create(project.path);

      final cancelledAnalysis = service.analyze(
        targetPath: 'lib',
        checks: 'complexity',
      );
      service.cancelCurrentAnalysis();

      await expectLater(
        cancelledAnalysis,
        throwsA(
          isA<McpAnalysisException>().having(
            (error) => error.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
      final nextResult = await service.analyze(
        targetPath: 'lib',
        checks: 'complexity',
      );
      expect(nextResult['target'], 'lib');
    });

    test('rejects traversal on every platform', () async {
      final container = await Directory.systemTemp.createTemp('hyena_mcp_');
      addTearDown(() => container.delete(recursive: true));
      final project = await _createProject(parent: container);
      final service = await McpAnalysisService.create(project.path);

      await expectLater(
        service.analyze(targetPath: '../outside', checks: 'complexity'),
        throwsA(
          isA<McpAnalysisException>().having(
            (error) => error.message,
            'message',
            contains('outside'),
          ),
        ),
      );
    });

    test(
      'rejects symlink escapes',
      () async {
        final container = await Directory.systemTemp.createTemp('hyena_mcp_');
        addTearDown(() => container.delete(recursive: true));
        final project = await _createProject(parent: container);
        final outside = Directory(p.join(container.path, 'outside'))
          ..createSync();
        File(
          p.join(outside.path, 'outside.dart'),
        ).writeAsStringSync('void x() {}');
        final service = await McpAnalysisService.create(project.path);

        final link = Link(p.join(project.path, 'lib', 'linked'));
        await link.create(outside.path);
        await expectLater(
          service.analyze(targetPath: 'lib', checks: 'complexity'),
          throwsA(
            isA<McpAnalysisException>().having(
              (error) => error.message,
              'message',
              contains('symbolic links'),
            ),
          ),
        );
      },
      skip: Platform.isWindows
          ? 'Symlink creation may require privileges'
          : false,
    );

    test('bounds input paths and source-controlled output strings', () async {
      final project = await _createProject();
      addTearDown(() => project.delete(recursive: true));
      final longName = 'a' * 5000;
      File(p.join(project.path, 'lib', 'example.dart')).writeAsStringSync('''
void $longName() {}
''');
      final service = await McpAnalysisService.create(project.path);

      await expectLater(
        service.analyze(targetPath: 'a' * 4097, checks: 'complexity'),
        throwsA(
          isA<McpAnalysisException>().having(
            (error) => error.message,
            'message',
            contains('character safety limit'),
          ),
        ),
      );
      await expectLater(
        service.analyze(targetPath: 'lib\u0000', checks: 'complexity'),
        throwsA(
          isA<McpAnalysisException>().having(
            (error) => error.message,
            'message',
            contains('NUL'),
          ),
        ),
      );

      final result = await service.analyze(
        targetPath: 'lib',
        checks: 'complexity',
      );
      final finding = (result['findings'] as List).single as Map;
      expect(finding['symbol'], hasLength(4096));
      expect(finding['message'], hasLength(4096));
      expect(finding['symbol'], endsWith('…'));
      expect(finding['message'], endsWith('…'));
    });

    test('does not discover configuration above its workspace root', () async {
      final container = await Directory.systemTemp.createTemp('hyena_mcp_');
      addTearDown(() => container.delete(recursive: true));
      File(p.join(container.path, 'hyena.yaml')).writeAsStringSync('''
hyena:
  complexity:
    cyclomatic_threshold: 0
''');
      final project = await _createProject(
        parent: container,
        withConfig: false,
      );

      final config = await AnalyzerConfig.load(
        null,
        targetPath: p.join(project.path, 'lib'),
        searchBoundary: project.path,
      );

      expect(config.cyclomaticThreshold, 20);
    });

    test(
      'rejects configuration symlinks outside its workspace root',
      () async {
        final container = await Directory.systemTemp.createTemp('hyena_mcp_');
        addTearDown(() => container.delete(recursive: true));
        final project = await _createProject(
          parent: container,
          withConfig: false,
        );
        final outsideConfig = File(p.join(container.path, 'outside.yaml'))
          ..writeAsStringSync('hyena: {}');
        await Link(
          p.join(project.path, 'hyena.yaml'),
        ).create(outsideConfig.path);

        await expectLater(
          AnalyzerConfig.load(
            null,
            targetPath: p.join(project.path, 'lib'),
            searchBoundary: project.path,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
      skip: Platform.isWindows
          ? 'Symlink creation may require privileges'
          : false,
    );
  });

  test(
    'stdio server exposes and executes only the read-only Hyena tool',
    () async {
      final project = await _createProject();
      addTearDown(() => project.delete(recursive: true));
      final pubGet = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: project.path);
      expect(pubGet.exitCode, 0, reason: pubGet.stderr as String);
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/hyena_mcp.dart',
        '--root',
        project.path,
      ], workingDirectory: Directory.current.path);
      addTearDown(() => process.kill());
      final stderrOutput = StringBuffer();
      final stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(stderrOutput.write);
      addTearDown(stderrSubscription.cancel);

      final client = MCPClient(
        Implementation(name: 'hyena-test-client', version: '1.0.0'),
      );
      final connection = client.connectServer(
        stdioChannel(input: process.stdout, output: process.stdin),
      );
      final initializeResult = await connection
          .initialize(
            InitializeRequest(
              protocolVersion: ProtocolVersion.latestSupported,
              capabilities: client.capabilities,
              clientInfo: client.implementation,
            ),
          )
          .timeout(const Duration(seconds: 20));
      expect(initializeResult.capabilities.tools, isNotNull);
      expect(initializeResult.serverInfo.version, hyenaVersion);
      connection.notifyInitialized();

      final tools = await connection.listTools(ListToolsRequest());
      expect(tools.tools, hasLength(1));
      final tool = tools.tools.single;
      expect(tool.name, 'hyena_analyze');
      expect(tool.toolAnnotations?.readOnlyHint, isTrue);
      expect(tool.toolAnnotations?.openWorldHint, isFalse);
      expect(tool.outputSchema, isNotNull);

      final result = await connection
          .callTool(
            CallToolRequest(
              name: tool.name,
              arguments: {'path': 'lib', 'checks': 'both'},
            ),
          )
          .timeout(const Duration(seconds: 20));
      expect(result.isError, isNot(isTrue));
      final structured = result.structuredContent;
      expect(structured, isNotNull);
      expect(tool.outputSchema!.validate(structured), isEmpty);
      expect(structured!['target'], 'lib');

      final escaped = await connection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {'path': '../outside', 'checks': 'both'},
        ),
      );
      expect(escaped.isError, isTrue);
      expect(escaped.structuredContent, isNull);

      final invalid = await connection.callTool(
        CallToolRequest(name: tool.name, arguments: {'unexpected': true}),
      );
      expect(invalid.isError, isTrue);

      const untrustedMarker = 'source-controlled-secret-marker';
      File(p.join(project.path, 'lib', 'example.dart')).writeAsStringSync('''
import '$untrustedMarker.dart';
''');
      final analysisError = await connection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {'path': 'lib', 'checks': 'dead-code'},
        ),
      );
      expect(analysisError.isError, isTrue);

      await client.shutdown().timeout(const Duration(seconds: 10));
      final processExitCode = await process.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          process.kill();
          return process.exitCode;
        },
      );
      expect(processExitCode, 0, reason: stderrOutput.toString());
      expect(stderrOutput.toString(), isNot(contains(untrustedMarker)));
    },
  );
}

Future<Directory> _createProject({
  Directory? parent,
  bool withConfig = true,
}) async {
  final project = parent == null
      ? await Directory.systemTemp.createTemp('hyena_mcp_project_')
      : await Directory(
          p.join(
            parent.path,
            'project_${DateTime.now().microsecondsSinceEpoch}',
          ),
        ).create();
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: hyena_mcp_fixture
environment:
  sdk: ^3.10.0
''');
  if (withConfig) {
    File(p.join(project.path, 'hyena.yaml')).writeAsStringSync('''
hyena:
  complexity:
    cyclomatic_threshold: 0
    max_nesting: 0
    max_parameters: 0
''');
  }
  final lib = Directory(p.join(project.path, 'lib'))..createSync();
  File(p.join(lib.path, 'example.dart')).writeAsStringSync('''
int calculate(bool first, bool second) {
  if (first) {
    return 1;
  }
  if (second) {
    return 2;
  }
  return 0;
}
''');
  return project;
}
