import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../models/complexity_metrics.dart';

class ComplexityVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final List<FunctionMetrics> functions = [];
  String? _currentClass;

  ComplexityVisitor(this.filePath);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _currentClass = node.name.lexeme;
    super.visitClassDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _currentClass = node.name.lexeme;
    super.visitMixinDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _currentClass = node.name?.lexeme;
    super.visitExtensionDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final body = node.functionExpression.body;
    final params = node.functionExpression.parameters;

    functions.add(
      _analyzeFunction(
        name: node.name.lexeme,
        body: body,
        parameters: params,
        offset: node.offset,
        end: node.end,
      ),
    );

    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final body = node.body;
    final params = node.parameters;

    functions.add(
      _analyzeFunction(
        name: node.name.lexeme,
        body: body,
        parameters: params,
        offset: node.offset,
        end: node.end,
        parentClass: _currentClass,
      ),
    );

    super.visitMethodDeclaration(node);
  }

  FunctionMetrics _analyzeFunction({
    required String name,
    required FunctionBody body,
    FormalParameterList? parameters,
    required int offset,
    required int end,
    String? parentClass,
  }) {
    final complexityCounter = _CyclomaticComplexityCounter();
    body.accept(complexityCounter);

    final nestingCounter = _NestingLevelCounter();
    body.accept(nestingCounter);

    final loc = _countLinesOfCode(body);
    final paramCount = parameters?.parameters.length ?? 0;

    return FunctionMetrics(
      name: name,
      filePath: filePath,
      line: offset,
      cyclomaticComplexity: complexityCounter.complexity,
      linesOfCode: loc,
      maxNestingLevel: nestingCounter.maxLevel,
      parameterCount: paramCount,
      parentClass: parentClass,
    );
  }

  int _countLinesOfCode(FunctionBody body) {
    final source = body.toSource();
    return source.split('\n').where((line) => line.trim().isNotEmpty).length;
  }
}

class _CyclomaticComplexityCounter extends RecursiveAstVisitor<void> {
  int complexity = 1;

  @override
  void visitIfStatement(IfStatement node) {
    complexity++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    complexity++;
    super.visitForStatement(node);
  }

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    complexity++;
    super.visitForEachPartsWithDeclaration(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    complexity++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    complexity++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    complexity++;
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    complexity++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    complexity++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    complexity++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||' || op == '??') {
      complexity++;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitAssertStatement(AssertStatement node) {
    complexity++;
    super.visitAssertStatement(node);
  }
}

class _NestingLevelCounter extends RecursiveAstVisitor<void> {
  int _currentLevel = 0;
  int maxLevel = 0;

  void _incrementLevel() {
    _currentLevel++;
    if (_currentLevel > maxLevel) {
      maxLevel = _currentLevel;
    }
  }

  void _decrementLevel() {
    _currentLevel--;
  }

  @override
  void visitIfStatement(IfStatement node) {
    _incrementLevel();
    super.visitIfStatement(node);
    _decrementLevel();
  }

  @override
  void visitForStatement(ForStatement node) {
    _incrementLevel();
    super.visitForStatement(node);
    _decrementLevel();
  }

  @override
  void visitForElement(ForElement node) {
    _incrementLevel();
    super.visitForElement(node);
    _decrementLevel();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _incrementLevel();
    super.visitWhileStatement(node);
    _decrementLevel();
  }

  @override
  void visitDoStatement(DoStatement node) {
    _incrementLevel();
    super.visitDoStatement(node);
    _decrementLevel();
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _incrementLevel();
    super.visitSwitchStatement(node);
    _decrementLevel();
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _incrementLevel();
    super.visitSwitchExpression(node);
    _decrementLevel();
  }

  @override
  void visitTryStatement(TryStatement node) {
    _incrementLevel();
    super.visitTryStatement(node);
    _decrementLevel();
  }

}
