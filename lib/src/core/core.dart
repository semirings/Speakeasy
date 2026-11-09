/// Speakeasy base language: lexer, parser, AST, runtime.
///
/// Rule: nothing under `core/` may import from `extensions/`.
/// Enforced by test/layering_test.dart.
library;

export 'ast.dart';
export 'errors.dart';
export 'host.dart';
export 'lexer.dart';
export 'parser.dart';
export 'runtime.dart';
export 'values.dart';
