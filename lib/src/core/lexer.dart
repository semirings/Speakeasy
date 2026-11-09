/// Lexer for Speakeasy base. See grammar/base.ebnf, section 1.
///
/// Keywords are not recognised here: every name is a [TokenType.word] and the
/// parser decides (keywords are case-insensitive, see [Token.lower]).
library;

import 'errors.dart';

enum TokenType { word, number, string, symbol, newline, eof }

class Token {
  const Token(this.type, this.text, this.line, this.column);

  final TokenType type;

  /// Source text. For a string this is the content without the quotes.
  final String text;
  final int line;
  final int column;

  String get lower => text.toLowerCase();

  bool isWord(String lowerCaseWord) =>
      type == TokenType.word && lower == lowerCaseWord;

  bool isSymbol(String s) => type == TokenType.symbol && text == s;

  @override
  String toString() {
    switch (type) {
      case TokenType.eof:
        return 'end of script';
      case TokenType.newline:
        return 'end of line';
      case TokenType.string:
        return '"$text"';
      default:
        return "'$text'";
    }
  }
}

bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isAlpha(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;

/// Splits [source] into tokens. The last token is always [TokenType.eof].
/// Comments (`--`) and continuations (`¬` at end of line) are removed.
/// `≠ ≤ ≥` are returned as `<>`, `<=`, `>=`.
List<Token> tokenize(String source) {
  final List<Token> out = <Token>[];
  final int n = source.length;
  int i = 0;
  int line = 1;
  int lineStart = 0;

  void add(TokenType type, String text, int start) {
    out.add(Token(type, text, line, start - lineStart + 1));
  }

  ParseError fail(String message, int at) =>
      ParseError(message, line: line, column: at - lineStart + 1);

  while (i < n) {
    final int c = source.codeUnitAt(i);

    if (c == 32 || c == 9 || c == 0xA0) {
      i++;
      continue;
    }

    if (c == 13 || c == 10) {
      final int start = i;
      if (c == 13 && i + 1 < n && source.codeUnitAt(i + 1) == 10) i++;
      i++;
      add(TokenType.newline, '\n', start);
      line++;
      lineStart = i;
      continue;
    }

    // Comment: -- to end of line.
    if (c == 45 && i + 1 < n && source.codeUnitAt(i + 1) == 45) {
      while (i < n && source.codeUnitAt(i) != 10 && source.codeUnitAt(i) != 13) {
        i++;
      }
      continue;
    }

    // Continuation: ¬ then optional spaces then a newline.
    if (c == 0xAC) {
      int j = i + 1;
      while (j < n && (source.codeUnitAt(j) == 32 || source.codeUnitAt(j) == 9)) {
        j++;
      }
      if (j < n && (source.codeUnitAt(j) == 13 || source.codeUnitAt(j) == 10)) {
        if (source.codeUnitAt(j) == 13 &&
            j + 1 < n &&
            source.codeUnitAt(j + 1) == 10) {
          j++;
        }
        j++;
        i = j;
        line++;
        lineStart = i;
        continue;
      }
      throw fail("'¬' must be the last thing on a line", i);
    }

    // String: "..." on one line, no escapes.
    if (c == 34) {
      final int start = i;
      int j = i + 1;
      while (j < n && source.codeUnitAt(j) != 34) {
        final int d = source.codeUnitAt(j);
        if (d == 10 || d == 13) throw fail('unterminated string', start);
        j++;
      }
      if (j >= n) throw fail('unterminated string', start);
      add(TokenType.string, source.substring(i + 1, j), start);
      i = j + 1;
      continue;
    }

    // Number: 12  12.5  12.  .5  1e3  1.5E-2
    if (_isDigit(c) ||
        (c == 46 && i + 1 < n && _isDigit(source.codeUnitAt(i + 1)))) {
      final int start = i;
      int j = i;
      while (j < n && _isDigit(source.codeUnitAt(j))) {
        j++;
      }
      if (j < n && source.codeUnitAt(j) == 46) {
        j++;
        while (j < n && _isDigit(source.codeUnitAt(j))) {
          j++;
        }
      }
      if (j < n && (source.codeUnitAt(j) == 101 || source.codeUnitAt(j) == 69)) {
        int k = j + 1;
        if (k < n && (source.codeUnitAt(k) == 43 || source.codeUnitAt(k) == 45)) {
          k++;
        }
        if (k < n && _isDigit(source.codeUnitAt(k))) {
          while (k < n && _isDigit(source.codeUnitAt(k))) {
            k++;
          }
          j = k;
        }
      }
      add(TokenType.number, source.substring(start, j), start);
      i = j;
      continue;
    }

    // Word: letters, digits, underscore.
    if (_isAlpha(c)) {
      final int start = i;
      int j = i + 1;
      while (j < n &&
          (_isAlpha(source.codeUnitAt(j)) || _isDigit(source.codeUnitAt(j)))) {
        j++;
      }
      add(TokenType.word, source.substring(start, j), start);
      i = j;
      continue;
    }

    // Symbols.
    final int start = i;
    final String two = i + 1 < n ? source.substring(i, i + 2) : '';
    if (two == '<=' || two == '>=' || two == '<>' || two == '&&') {
      add(TokenType.symbol, two, start);
      i += 2;
      continue;
    }
    switch (c) {
      case 0x2260: // ≠
        add(TokenType.symbol, '<>', start);
        i++;
        continue;
      case 0x2264: // ≤
        add(TokenType.symbol, '<=', start);
        i++;
        continue;
      case 0x2265: // ≥
        add(TokenType.symbol, '>=', start);
        i++;
        continue;
    }
    final String one = source[i];
    if ('+-*/^=<>(),&'.contains(one)) {
      add(TokenType.symbol, one, start);
      i++;
      continue;
    }

    throw fail("unexpected character '$one'", i);
  }

  out.add(Token(TokenType.eof, '', line, i - lineStart + 1));
  return out;
}
