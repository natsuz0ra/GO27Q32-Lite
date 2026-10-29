// Maintenance tool: run using the Flutter tools package configuration, which
// supplies package:analyzer. No analyzer dependency is shipped with the app.
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Strings extends RecursiveAstVisitor<void> {
  final entries = <String>{};
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(node.value))
      entries.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    var index = 0;
    final text = node.elements
        .map((e) => e is InterpolationString ? e.value : '{${index++}}')
        .join();
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) entries.add(text);
    // Nested literals are labels/branches too.
    super.visitStringInterpolation(node);
  }
}

class Rewrite extends RecursiveAstVisitor<void> {
  final edits = <int, (int, String)>{};
  void removeConst(AstNode? node) {
    while (node != null) {
      if (node is InstanceCreationExpression &&
          node.keyword?.lexeme == 'const') {
        edits[node.keyword!.offset] = (node.keyword!.length, '');
      }
      if (node is ListLiteral && node.constKeyword != null) {
        edits[node.constKeyword!.offset] = (node.constKeyword!.length, '');
      }
      node = node.parent;
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    final name = type.toSource();
    if (['Text', 'Tooltip', 'SelectableText'].contains(name)) {
      final positional = node.argumentList.arguments
          .where((a) => a is! NamedExpression)
          .firstOrNull;
      final source = positional?.toSource() ?? '';
      // Names supplied by the user are data, never translation keys.
      final userName = RegExp(
        r'''(?:p|profile|draft|item)\['(?:Name|name)'\]''',
      ).hasMatch(source);
      if (!userName) edits[type.offset] = (type.length, 'L$name');
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (['Text', 'Tooltip', 'SelectableText'].contains(name)) {
      final positional = node.argumentList.arguments.where((a) => a is! NamedExpression).firstOrNull;
      final source = positional?.toSource() ?? '';
      final userName = RegExp(r'''(?:p|profile|draft|item)\['(?:Name|name)'\]''').hasMatch(source);
      if (!userName) edits[node.methodName.offset] = (node.methodName.length, 'L$name');
    }
    super.visitMethodInvocation(node);
  }
  @override
  void visitNamedExpression(NamedExpression node) {
    if ([
          'labelText',
          'hintText',
          'helperText',
          'tooltip',
        ].contains(node.name.label.name) &&
        node.expression is StringLiteral &&
        RegExp(r'[\u4e00-\u9fff]').hasMatch(node.expression.toSource())) {
      edits[node.expression.offset] = (
        node.expression.length,
        'tr(context, ${node.expression.toSource()})',
      );
      removeConst(node);
    }
    super.visitNamedExpression(node);
  }
}

void main(List<String> args) {
  if (args.first == '--apply') {
    for (final name in ['app', 'ui_parts', 'editors', 'hdr_probe', 'main']) {
      final file = File('lib/$name.dart');
      var source = file.readAsStringSync();
      final rewrite = Rewrite();
      parseString(content: source, path: file.path).unit.accept(rewrite);
      for (final offset
          in rewrite.edits.keys.toList()..sort((a, b) => b.compareTo(a))) {
        final edit = rewrite.edits[offset]!;
        source = source.replaceRange(offset, offset + edit.$1, edit.$2);
      }
      if (!source.contains("import 'l10n.dart';"))
        source = "import 'l10n.dart';\n$source";
      file.writeAsStringSync(source);
      stdout.writeln('${file.path}: ${rewrite.edits.length} edits');
    }
    return;
  }
  final all = <String>{};
  for (final entity
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    final visitor = Strings();
    parseString(
      content: entity.readAsStringSync(),
      path: entity.path,
    ).unit.accept(visitor);
    all.addAll(visitor.entries);
  }
  final sorted = all.toList()..sort();
  File(args.first).writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({for (final text in sorted) text: ''}),
  );
  stdout.writeln('${sorted.length} source messages');
}
