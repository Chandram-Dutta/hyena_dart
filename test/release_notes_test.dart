import 'package:test/test.dart';

import '../tool/release_notes.dart';

const _changelog = '''
# Changelog

## [Unreleased]

## [3.0.1] - 2026-12-01

### Fixed
- Second fix.

## [3.0.0] - 2026-11-11

   

## [2.0.0] - 2026-08-30
### Added
- Feature.
''';

void main() {
  group('extractReleaseNotes', () {
    test('returns the populated section without its heading', () {
      expect(
        extractReleaseNotes(_changelog, '3.0.1'),
        '### Fixed\n- Second fix.',
      );
    });

    test('returns the last section up to end of file', () {
      expect(extractReleaseNotes(_changelog, '2.0.0'), '### Added\n- Feature.');
    });

    test('rejects a whitespace-only section', () {
      expect(extractReleaseNotes(_changelog, '3.0.0'), isNull);
    });

    test('rejects a missing or unbracketed section', () {
      expect(extractReleaseNotes(_changelog, '9.9.9'), isNull);
      expect(extractReleaseNotes('## 3.0.1\n- Fix.\n', '3.0.1'), isNull);
    });

    test('does not match a version prefix', () {
      expect(extractReleaseNotes(_changelog, '3.0'), isNull);
    });

    test('keeps indentation of a leading code block', () {
      expect(
        extractReleaseNotes(
          '## [1.0.0]\n\n    dart run hyena_dart\n    more\n\n## [0.9.0]\n',
          '1.0.0',
        ),
        '    dart run hyena_dart\n    more',
      );
    });

    test('handles CRLF line endings', () {
      expect(
        extractReleaseNotes('## [1.0.0]\r\n- Fix.\r\n## [0.9.0]\r\n', '1.0.0'),
        '- Fix.',
      );
    });
  });
}
