import 'dart:convert';
import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../models/complexity_metrics.dart';

class ComplexityVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final LineInfo lineInfo;
  final List<FunctionMetrics> functions = [];
  String? _currentClass;

  ComplexityVisitor(this.filePath, this.lineInfo);

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
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _currentClass = node.name.lexeme;
    super.visitExtensionTypeDeclaration(node);
    _currentClass = null;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _currentClass = node.name.lexeme;
    super.visitEnumDeclaration(node);
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
        parentClass: node.parent is FunctionDeclarationStatement
            ? _currentClass
            : null,
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
        parentClass: _currentClass,
      ),
    );

    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    functions.add(
      _analyzeFunction(
        name: node.name?.lexeme ?? 'new',
        body: node.body,
        parameters: node.parameters,
        offset: node.name?.offset ?? node.returnType.offset,
        parentClass: _currentClass,
      ),
    );

    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is! FunctionDeclaration) {
      final location = lineInfo.getLocation(node.offset);
      functions.add(
        _analyzeFunction(
          name: '<closure@${location.lineNumber}:${location.columnNumber}>',
          body: node.body,
          parameters: node.parameters,
          offset: node.offset,
          parentClass: _currentClass,
        ),
      );
    }

    super.visitFunctionExpression(node);
  }

  FunctionMetrics _analyzeFunction({
    required String name,
    required FunctionBody body,
    FormalParameterList? parameters,
    required int offset,
    String? parentClass,
  }) {
    final complexityCounter = _CyclomaticComplexityCounter();
    body.accept(complexityCounter);

    final nestingCounter = _NestingLevelCounter();
    body.accept(nestingCounter);

    final loc = _countLinesOfCode(body);
    final paramCount = parameters?.parameters.length ?? 0;
    final location = lineInfo.getLocation(offset);

    return FunctionMetrics(
      name: name,
      filePath: filePath,
      line: location.lineNumber,
      cyclomaticComplexity: complexityCounter.complexity,
      linesOfCode: loc,
      maxNestingLevel: nestingCounter.maxLevel,
      parameterCount: paramCount,
      halsteadVolume: _calculateHalsteadVolume(body),
      parentClass: parentClass,
    );
  }

  int _countLinesOfCode(FunctionBody body) {
    final source = body.toSource();
    return const LineSplitter()
        .convert(source)
        .where((line) => line.trim().isNotEmpty)
        .length;
  }

  double _calculateHalsteadVolume(FunctionBody body) {
    final uniqueOperators = <String>{};
    final uniqueOperands = <String>{};
    var operatorCount = 0;
    var operandCount = 0;
    var token = body.beginToken;

    while (true) {
      if (_isOperand(token)) {
        uniqueOperands.add(token.lexeme);
        operandCount++;
      } else if (_isOperator(token)) {
        uniqueOperators.add(token.lexeme);
        operatorCount++;
      }
      if (identical(token, body.endToken)) break;
      final next = token.next;
      if (next == null) break;
      token = next;
    }

    final vocabulary = uniqueOperators.length + uniqueOperands.length;
    final length = operatorCount + operandCount;
    if (vocabulary == 0 || length == 0) return 0;
    return length * (math.log(vocabulary) / math.ln2);
  }

  bool _isOperand(Token token) {
    if (token.isIdentifier ||
        const {
          'true',
          'false',
          'null',
          'this',
          'super',
        }.contains(token.lexeme)) {
      return true;
    }
    return token.type == TokenType.DOUBLE ||
        token.type == TokenType.DOUBLE_WITH_SEPARATORS ||
        token.type == TokenType.HEXADECIMAL ||
        token.type == TokenType.HEXADECIMAL_WITH_SEPARATORS ||
        token.type == TokenType.INT ||
        token.type == TokenType.INT_WITH_SEPARATORS ||
        token.type == TokenType.STRING;
  }

  bool _isOperator(Token token) {
    if (const {'{', '}', '(', ')', '[', ']', ',', ';'}.contains(token.lexeme)) {
      return false;
    }
    return token.isOperator || token.type.isKeyword;
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
  void visitForElement(ForElement node) {
    complexity++;
    super.visitForElement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    complexity++;
    super.visitIfElement(node);
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
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    complexity++;
    super.visitSwitchExpressionCase(node);
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

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {}
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
  void visitIfElement(IfElement node) {
    _incrementLevel();
    super.visitIfElement(node);
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

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}
