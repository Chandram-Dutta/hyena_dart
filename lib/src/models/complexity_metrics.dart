class FunctionMetrics {
  final String name;
  final String filePath;
  final int line;
  final int cyclomaticComplexity;
  final int linesOfCode;
  final int maxNestingLevel;
  final int parameterCount;
  final String? parentClass;

  FunctionMetrics({
    required this.name,
    required this.filePath,
    required this.line,
    required this.cyclomaticComplexity,
    required this.linesOfCode,
    required this.maxNestingLevel,
    required this.parameterCount,
    this.parentClass,
  });

  String get fullName => parentClass != null ? '$parentClass.$name' : name;

  double get maintainabilityIndex {
    final halsteadVolume = linesOfCode * 3.0;
    final mi =
        171 -
        5.2 * _log2(halsteadVolume) -
        0.23 * cyclomaticComplexity -
        16.2 * _log2(linesOfCode);
    return mi.clamp(0, 100);
  }

  static double _log2(num x) => x > 0 ? _ln(x) / _ln(2) : 0;
  static double _ln(num x) {
    if (x <= 0) return 0;
    double result = 0;
    double term = (x - 1) / (x + 1);
    double termSquared = term * term;
    double currentTerm = term;
    for (int i = 1; i <= 100; i += 2) {
      result += currentTerm / i;
      currentTerm *= termSquared;
    }
    return 2 * result;
  }

  Map<String, dynamic> toJson() => {
    'name': fullName,
    'filePath': filePath,
    'line': line,
    'cyclomaticComplexity': cyclomaticComplexity,
    'linesOfCode': linesOfCode,
    'maxNestingLevel': maxNestingLevel,
    'parameterCount': parameterCount,
    'maintainabilityIndex': maintainabilityIndex.toStringAsFixed(2),
  };
}

class FileMetrics {
  final String filePath;
  final int totalLines;
  final int codeLines;
  final int commentLines;
  final int blankLines;
  final List<FunctionMetrics> functions;

  FileMetrics({
    required this.filePath,
    required this.totalLines,
    required this.codeLines,
    required this.commentLines,
    required this.blankLines,
    required this.functions,
  });

  double get averageCyclomaticComplexity {
    if (functions.isEmpty) return 0;
    return functions
            .map((f) => f.cyclomaticComplexity)
            .reduce((a, b) => a + b) /
        functions.length;
  }

  int get maxCyclomaticComplexity {
    if (functions.isEmpty) return 0;
    return functions
        .map((f) => f.cyclomaticComplexity)
        .reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'totalLines': totalLines,
    'codeLines': codeLines,
    'commentLines': commentLines,
    'blankLines': blankLines,
    'averageCyclomaticComplexity': averageCyclomaticComplexity.toStringAsFixed(
      2,
    ),
    'maxCyclomaticComplexity': maxCyclomaticComplexity,
    'functions': functions.map((f) => f.toJson()).toList(),
  };
}

class ComplexityReport {
  final List<FileMetrics> files;
  final DateTime analyzedAt;

  ComplexityReport({required this.files, DateTime? analyzedAt})
    : analyzedAt = analyzedAt ?? DateTime.now();

  int get totalFiles => files.length;
  int get totalFunctions => files.fold(0, (sum, f) => sum + f.functions.length);
  int get totalLines => files.fold(0, (sum, f) => sum + f.totalLines);

  List<FunctionMetrics> get highComplexityFunctions {
    return files
        .expand((f) => f.functions)
        .where((f) => f.cyclomaticComplexity > 10)
        .toList()
      ..sort(
        (a, b) => b.cyclomaticComplexity.compareTo(a.cyclomaticComplexity),
      );
  }

  Map<String, dynamic> toJson() => {
    'analyzedAt': analyzedAt.toIso8601String(),
    'summary': {
      'totalFiles': totalFiles,
      'totalFunctions': totalFunctions,
      'totalLines': totalLines,
      'highComplexityFunctions': highComplexityFunctions.length,
    },
    'files': files.map((f) => f.toJson()).toList(),
  };
}
