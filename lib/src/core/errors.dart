/// Errors raised while reading or running Speakeasy.
library;

/// Base class. [line] and [column] are 1-based when known.
class SpeakeasyError implements Exception {
  SpeakeasyError(this.message, {this.line, this.column});

  final String message;
  final int? line;
  final int? column;

  @override
  String toString() => line == null ? message : 'line $line: $message';
}

/// The text is not valid Speakeasy (lexer or parser).
class ParseError extends SpeakeasyError {
  ParseError(super.message, {super.line, super.column});
}

/// A script failed while running (type error, missing object, ...).
class ScriptError extends SpeakeasyError {
  ScriptError(super.message, {super.line});
}
