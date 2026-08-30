import 'package:path/path.dart' as p;

const _defaultExcludedDirectories = {
  '.dart_tool',
  '.delta',
  '.fvm',
  '.git',
  '.hg',
  '.jj',
  '.svn',
  'build',
  'generated',
};

bool isDefaultExcludedSourcePath(String relativePath) {
  final normalizedPath = p.normalize(relativePath);
  final fileName = p.basename(normalizedPath);
  if (fileName.endsWith('.g.dart') ||
      fileName.endsWith('.freezed.dart') ||
      fileName.endsWith('.mocks.dart')) {
    return true;
  }

  return p.split(normalizedPath).any(_defaultExcludedDirectories.contains);
}
