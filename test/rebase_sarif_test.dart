import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/github_action/rebase_sarif.dart' as rebase;

void main() {
  test(
    'rebases finding and invocation notification locations consistently',
    () {
      final root = Directory.systemTemp.createTempSync('hyena_rebase_');
      addTearDown(() => root.deleteSync(recursive: true));
      final package = Directory(p.join(root.path, 'packages', 'example'))
        ..createSync(recursive: true);
      File(
        p.join(package.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: example');
      Map<String, dynamic> entry() => {
        'locations': [
          for (final uri in [
            'lib/a%20b.dart',
            'file:///external.dart',
            '/absolute.dart',
          ])
            {
              'physicalLocation': {
                'artifactLocation': {'uri': uri},
              },
            },
          {'physicalLocation': {}},
        ],
      };
      final report = File(p.join(root.path, 'report.sarif'));
      report.writeAsStringSync(
        jsonEncode({
          'runs': [
            {
              'results': [entry()],
              'invocations': [
                {
                  'toolExecutionNotifications': [entry()],
                },
                {},
              ],
            },
            {},
          ],
        }),
      );

      rebase.main([report.path, package.path, root.path]);

      final run = (jsonDecode(report.readAsStringSync()) as Map)['runs'][0];
      for (final value in [
        run['results'][0],
        run['invocations'][0]['toolExecutionNotifications'][0],
      ]) {
        final locations = value['locations'];
        expect(
          locations[0]['physicalLocation']['artifactLocation']['uri'],
          'packages/example/lib/a%20b.dart',
        );
        expect(
          locations[1]['physicalLocation']['artifactLocation']['uri'],
          'file:///external.dart',
        );
        expect(
          locations[2]['physicalLocation']['artifactLocation']['uri'],
          '/absolute.dart',
        );
        expect(locations[3]['physicalLocation'], isEmpty);
      }
    },
  );
}
