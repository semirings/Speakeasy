/// Recursive-descent parser for Speakeasy base (grammar/base.ebnf, DRAFT 2).
///
/// Two entry points:
///   [Parser.parseScript]      the text of a script: `on ... end` handlers
///   [Parser.parseStatements]  statements typed in the message box
///
/// Extensions (d4m, blender) will register extra commands later; this file
/// handles base only.
library;

import 'dart:math' as math;

import 'ast.dart';
import 'errors.dart';
import 'lexer.dart';

/// Words that cannot be used as variable, handler or parameter names (D2).
const Set<String> _reserved = <String>{
  // structure
  'on', 'end', 'function', 'if', 'then', 'else', 'repeat', 'forever', 'until',
  'while', 'for', 'times', 'with', 'down', 'to', 'do', 'exit', 'next', 'global',
  'pass', 'return', 'send',
  // operators and prepositions
  'and', 'or', 'not', 'mod', 'div', 'contains', 'is', 'in', 'there', 'of',
  'the', 'where', 'into', 'before', 'after', 'from', 'by',
  // constants
  'empty', 'true', 'false', 'quote', 'space', 'tab', 'linefeed', 'pi', 'up',
  // objects and parts
  'me', 'target', 'whetstone', 'card', 'cd', 'cards', 'cds', 'field', 'fld',
  'fields', 'flds', 'button', 'btn', 'buttons', 'btns', 'stack', 'char',
  'character', 'chars', 'characters', 'word', 'words', 'item', 'items', 'line',
  'lines', 'msg', 'message', 'selection', 'this', 'first', 'second', 'third',
  'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'last',
  'middle', 'any', 'prev', 'previous',
  // commands
  'add', 'answer', 'ask', 'beep', 'create', 'delete', 'divide', 'drop', 'find',
  'get', 'go', 'hide', 'multiply', 'put', 'save', 'set', 'show', 'sort',
  'subtract', 'wait',
};

const Set<String> _properties = <String>{
  'id', 'name', 'script', 'text', 'visible', 'number', 'score', 'itemdelimiter',
};

const Set<String> _theFunctions = <String>{
  'abs', 'average', 'date', 'length', 'max', 'min', 'number', 'offset', 'param',
  'paramcount', 'params', 'random', 'result', 'round', 'seconds', 'sqrt', 'sum',
  'target', 'ticks', 'time', 'trunc', 'value',
};

const Map<String, String> _units = <String, String>{
  'char': 'char',
  'character': 'char',
  'word': 'word',
  'item': 'item',
  'line': 'line',
};

/// Plural unit and part words, as accepted after `number of`.
const Map<String, String> _plurals = <String, String>{
  'cards': 'cards',
  'cds': 'cards',
  'fields': 'fields',
  'flds': 'fields',
  'buttons': 'buttons',
  'btns': 'buttons',
  'chars': 'chars',
  'characters': 'chars',
  'words': 'words',
  'items': 'items',
  'lines': 'lines',
};

const Map<String, int> _ordinals = <String, int>{
  'first': 1,
  'second': 2,
  'third': 3,
  'fourth': 4,
  'fifth': 5,
  'sixth': 6,
  'seventh': 7,
  'eighth': 8,
  'ninth': 9,
  'tenth': 10,
};

const Set<String> _positions = <String>{
  'next', 'prev', 'previous', 'this', 'last', 'any',
};

String? _partKind(String lower) {
  switch (lower) {
    case 'card':
    case 'cd':
      return 'card';
    case 'field':
    case 'fld':
      return 'field';
    case 'button':
    case 'btn':
      return 'button';
  }
  return null;
}

class Parser {
  Parser(String source) : _t = tokenize(source);

  final List<Token> _t;
  int _p = 0;

  /// Parses a whole script (zero or more handlers).
  static Script parseScript(String source) => Parser(source)._script();

  /// Parses statements, e.g. a line typed in the message box.
  static List<Stmt> parseStatements(String source) {
    final Parser p = Parser(source);
    final List<Stmt> out = <Stmt>[];
    while (p._cur.type != TokenType.eof) {
      final Stmt? s = p._statement();
      if (s != null) out.add(s);
    }
    return out;
  }

  // ------------------------------------------------------------- helpers

  Token get _cur => _t[_p];

  Token _at(int k) => _t[math.min(_p + k, _t.length - 1)];

  Token _next() {
    final Token t = _t[_p];
    if (_p < _t.length - 1) _p++;
    return t;
  }

  bool _isWord(String w, [int k = 0]) => _at(k).isWord(w);
  bool _isSym(String s, [int k = 0]) => _at(k).isSymbol(s);

  bool get _atEnd =>
      _cur.type == TokenType.newline || _cur.type == TokenType.eof;

  bool _accept(String w) {
    if (_isWord(w)) {
      _next();
      return true;
    }
    return false;
  }

  bool _acceptSym(String s) {
    if (_isSym(s)) {
      _next();
      return true;
    }
    return false;
  }

  void _expect(String w) {
    if (!_isWord(w)) throw _err("expected '$w' but found $_cur");
    _next();
  }

  void _expectSym(String s) {
    if (!_isSym(s)) throw _err("expected '$s' but found $_cur");
    _next();
  }

  ParseError _err(String message, [Token? at]) {
    final Token t = at ?? _cur;
    return ParseError(message, line: t.line, column: t.column);
  }

  void _skipNewlines() {
    while (_cur.type == TokenType.newline) {
      _next();
    }
  }

  void _endOfLine() {
    if (_cur.type == TokenType.newline) {
      _next();
    } else if (_cur.type != TokenType.eof) {
      throw _err('unexpected $_cur');
    }
  }

  String _ident(String what) {
    final Token t = _cur;
    if (t.type != TokenType.word) throw _err('expected $what but found $t');
    if (_reserved.contains(t.lower)) {
      throw _err("'${t.text}' is a reserved word and cannot be used as $what");
    }
    _next();
    return t.text;
  }

  /// First word after any newlines starting at the current token.
  String? _wordAfterNewlines() {
    int k = 0;
    while (_at(k).type == TokenType.newline) {
      k++;
    }
    final Token t = _at(k);
    return t.type == TokenType.word ? t.lower : null;
  }

  // ------------------------------------------------------------- scripts

  Script _script() {
    final List<Handler> handlers = <Handler>[];
    while (true) {
      _skipNewlines();
      if (_cur.type == TokenType.eof) break;
      handlers.add(_handler());
    }
    return Script(handlers);
  }

  Handler _handler() {
    final Token start = _cur;
    final bool isFunction;
    if (_accept('on')) {
      isFunction = false;
    } else if (_accept('function')) {
      isFunction = true;
    } else {
      throw _err("expected 'on' or 'function' but found $start");
    }
    final String name = _ident('a handler name');
    final List<String> params = <String>[];
    if (!_atEnd) {
      params.add(_ident('a parameter name'));
      while (_acceptSym(',')) {
        params.add(_ident('a parameter name'));
      }
    }
    _endOfLine();
    final List<Stmt> body = _block(const <String>{'end'});
    _expect('end');
    final Token endTok = _cur;
    final String endName = _ident('the handler name');
    if (endName.toLowerCase() != name.toLowerCase()) {
      throw _err("'end $endName' does not match 'on $name'", endTok);
    }
    _endOfLine();
    return Handler(name, isFunction, params, body, start.line);
  }

  List<Stmt> _block(Set<String> stops) {
    final List<Stmt> out = <Stmt>[];
    while (true) {
      if (_cur.type == TokenType.eof) {
        throw _err("unexpected end of script; missing 'end'");
      }
      if (_cur.type == TokenType.word && stops.contains(_cur.lower)) break;
      final Stmt? s = _statement();
      if (s != null) out.add(s);
    }
    return out;
  }

  // ---------------------------------------------------------- statements

  /// One statement including its line end. Returns null for a blank line.
  Stmt? _statement() {
    if (_cur.type == TokenType.newline) {
      _next();
      return null;
    }
    final Token t = _cur;
    if (t.type != TokenType.word) throw _err('unexpected $t');
    if (t.lower == 'if') return _if();
    if (t.lower == 'repeat') return _repeat();
    final Stmt s = _simple();
    _endOfLine();
    return s;
  }

  Stmt _if() {
    final int line = _next().line; // if
    final Expr cond = _expr();
    if (_cur.type == TokenType.newline && _wordAfterNewlines() == 'then') {
      _skipNewlines();
    }
    _expect('then');

    if (_cur.type == TokenType.newline) {
      _next();
      final List<Stmt> thenBody = _block(const <String>{'else', 'end'});
      List<Stmt> elseBody = const <Stmt>[];
      if (_accept('else')) {
        elseBody = _elseRest(allowBlock: true);
      } else {
        _expect('end');
        _expect('if');
        _endOfLine();
      }
      return If(line, cond, thenBody, elseBody);
    }

    // One-line form: if c then stmt [else stmt]
    final Stmt? first = _statement();
    final List<Stmt> thenBody = <Stmt>[if (first != null) first];
    List<Stmt> elseBody = const <Stmt>[];
    final int save = _p;
    _skipNewlines();
    if (_accept('else')) {
      elseBody = _elseRest(allowBlock: true);
    } else {
      _p = save;
    }
    return If(line, cond, thenBody, elseBody);
  }

  /// After 'else': either `NL stmts end if` or one statement.
  List<Stmt> _elseRest({required bool allowBlock}) {
    if (allowBlock && _cur.type == TokenType.newline) {
      _next();
      final List<Stmt> body = _block(const <String>{'end'});
      _expect('end');
      _expect('if');
      _endOfLine();
      return body;
    }
    final Stmt? s = _statement();
    return <Stmt>[if (s != null) s];
  }

  Stmt _repeat() {
    final int line = _next().line; // repeat
    String kind = 'forever';
    Expr? cond;
    Expr? count;
    String? variable;
    Expr? from;
    Expr? to;
    bool down = false;

    if (_atEnd) {
      kind = 'forever';
    } else if (_accept('forever')) {
      kind = 'forever';
    } else if (_accept('until')) {
      kind = 'until';
      cond = _expr();
    } else if (_accept('while')) {
      kind = 'while';
      cond = _expr();
    } else if (_accept('with')) {
      kind = 'with';
      variable = _ident('a variable name');
      _expectSym('=');
      from = _expr();
      down = _accept('down');
      _expect('to');
      to = _expr();
    } else {
      kind = 'times';
      _accept('for');
      count = _expr();
      _accept('times');
    }
    _endOfLine();
    final List<Stmt> body = _block(const <String>{'end'});
    _expect('end');
    _expect('repeat');
    _endOfLine();
    return Repeat(line, kind, body,
        cond: cond,
        count: count,
        variable: variable,
        from: from,
        to: to,
        down: down);
  }

  /// A statement without its line end.
  Stmt _simple() {
    final Token t = _cur;
    final int line = t.line;
    switch (t.lower) {
      case 'do':
        _next();
        return Do(line, _expr());
      case 'exit':
        _next();
        if (_accept('repeat')) return ExitRepeat(line);
        return ExitHandler(line, _ident('a handler name'));
      case 'next':
        _next();
        _expect('repeat');
        return NextRepeat(line);
      case 'global':
        _next();
        final List<String> names = <String>[_ident('a variable name')];
        while (_acceptSym(',')) {
          names.add(_ident('a variable name'));
        }
        return Global(line, names);
      case 'pass':
        _next();
        return Pass(line, _ident('a message name'));
      case 'return':
        _next();
        return Return(line, _atEnd ? null : _expr());
      case 'send':
        _next();
        final Expr message = _expr();
        _expect('to');
        return Send(line, message, _objectRef());

      case 'add':
        _next();
        final Expr addValue = _expr();
        _expect('to');
        return Arith(line, 'add', addValue, _textTarget());
      case 'subtract':
        _next();
        final Expr subValue = _expr();
        _expect('from');
        return Arith(line, 'subtract', subValue, _textTarget());
      case 'multiply':
        _next();
        final TextTarget mulTarget = _textTarget();
        _expect('by');
        return Arith(line, 'multiply', _expr(), mulTarget);
      case 'divide':
        _next();
        final TextTarget divTarget = _textTarget();
        _expect('by');
        return Arith(line, 'divide', _expr(), divTarget);

      case 'get':
        _next();
        return Get(line, _expr());
      case 'put':
        _next();
        final Expr value = _expr();
        String? mode;
        TextTarget? target;
        if (_isWord('into') || _isWord('before') || _isWord('after')) {
          mode = _next().lower;
          target = _textTarget();
        }
        return Put(line, value, mode, target);
      case 'set':
        return _set();

      case 'go':
        _next();
        _accept('to');
        if (_atStackStart(0)) return Go(line, _stackRef());
        return Go(line, _cardRef());
      case 'find':
        return _find();
      case 'drop':
        _next();
        return Drop(line, _cardRef());
      case 'sort':
        return _sort();

      case 'create':
        _next();
        final String? kind = _partKind(_cur.lower);
        if (_cur.type != TokenType.word || kind == null) {
          throw _err("expected 'card', 'button' or 'field' but found $_cur");
        }
        _next();
        return Create(line, kind, _atEnd ? null : _expr());
      case 'delete':
        _next();
        if (_atChunkStart()) {
          return DeleteText(line, _textTarget());
        }
        if (_atObjectStart()) return DeleteObject(line, _objectRef());
        return DeleteText(line, _textTarget());
      case 'save':
        _next();
        if (_partKind(_cur.lower) == 'card') _next();
        return Save(line);
      case 'show':
      case 'hide':
        _next();
        final bool show = t.lower == 'show';
        if (_isWord('msg') || _isWord('message')) {
          _next();
          if (!_isWord('box')) throw _err("expected 'box' but found $_cur");
          _next();
          return ShowHideMsgBox(line, show: show);
        }
        return ShowHide(line, _objectRef(), show: show);

      case 'answer':
        _next();
        final Expr text = _expr();
        final List<Expr> buttons = <Expr>[];
        if (_accept('with')) {
          // 'or' separates buttons here, so parse below the 'or' level.
          buttons.add(_and());
          while (buttons.length < 3 && _accept('or')) {
            buttons.add(_and());
          }
        }
        return Answer(line, text, buttons);
      case 'ask':
        _next();
        final Expr prompt = _expr();
        return Ask(line, prompt, _accept('with') ? _expr() : null);
      case 'beep':
        _next();
        return Beep(line, _atEnd ? null : _expr());
      case 'wait':
        _next();
        if (_accept('until')) return Wait(line, 'until', cond: _expr());
        if (_accept('while')) return Wait(line, 'while', cond: _expr());
        final Expr amount = _expr();
        String unit = 'ticks';
        if (_accept('ticks')) {
          unit = 'ticks';
        } else if (_accept('seconds')) {
          unit = 'seconds';
        }
        return Wait(line, 'time', amount: amount, unit: unit);
    }

    if (t.type == TokenType.word && !_reserved.contains(t.lower)) {
      _next();
      final List<Expr> args = <Expr>[];
      if (!_atEnd) {
        args.add(_expr());
        while (_acceptSym(',')) {
          args.add(_expr());
        }
      }
      return MessageSend(line, t.text, args);
    }
    throw _err('unexpected $t');
  }

  Stmt _set() {
    final int line = _next().line; // set
    _accept('the');
    final Token p = _cur;
    if (p.type != TokenType.word || !_properties.contains(p.lower)) {
      throw _err('expected a property name but found $p');
    }
    _next();
    _expect('of');
    final Expr target = _propertyTarget();
    _expect('to');
    return SetProp(line, p.lower, target, _expr());
  }

  /// After `of` in a property reference: an object, or chunks of a field.
  Expr _propertyTarget() {
    if (_atChunkStart()) {
      final List<ChunkItem> chunks = _chunks();
      final ObjectRef f = _objectRef();
      if (f is! PartRef || f.kind != 'field') {
        throw _err('expected a field after the chunk');
      }
      return ChunkExpr(chunks, f);
    }
    return _objectRef();
  }

  Stmt _find() {
    final int line = _next().line; // find
    if ((_isWord('cards') || _isWord('cds')) && _isWord('where', 1)) {
      _next();
      _next();
      final Expr where = _expr();
      StackRef? into;
      if (_accept('into')) into = _stackRef();
      return FindCards(line, where, into);
    }
    final Expr text = _expr();
    PartRef? field;
    if (_accept('in')) {
      final ObjectRef f = _objectRef();
      if (f is! PartRef || f.kind != 'field') {
        throw _err("expected a field after 'in'");
      }
      field = f;
    }
    return FindText(line, text, field);
  }

  Stmt _sort() {
    final int line = _next().line; // sort
    if (_isWord('cards') || _isWord('cds')) _next();
    bool descending = false;
    if (_accept('ascending')) {
      descending = false;
    } else if (_accept('descending')) {
      descending = true;
    }
    String? mode;
    if (_accept('text')) {
      mode = 'text';
    } else if (_accept('numeric')) {
      mode = 'numeric';
    }
    _expect('by');
    return Sort(line, _expr(), descending: descending, mode: mode);
  }

  // ------------------------------------------------------------ containers

  TextTarget _textTarget() {
    final List<ChunkItem> chunks = _chunks();
    return TextTarget(chunks, _simpleContainer());
  }

  Expr _simpleContainer() {
    final Token t = _cur;
    if (t.type != TokenType.word) throw _err('expected a container but found $t');
    switch (t.lower) {
      case 'msg':
      case 'message':
        _next();
        return const MsgRef();
      case 'selection':
        _next();
        return const SelectionRef();
    }
    if (_partKind(t.lower) == 'field' || _isOrdinalPart(0, 'field')) {
      return _objectRef();
    }
    return Variable(_ident('a container'));
  }

  bool _isOrdinalPart(int k, String kind) {
    final Token t = _at(k);
    return t.type == TokenType.word &&
        (_ordinals.containsKey(t.lower) || _positions.contains(t.lower)) &&
        _partKind(_at(k + 1).lower) == kind;
  }

  // ---------------------------------------------------------------- chunks

  bool _atChunkStart() {
    final Token t = _cur;
    if (t.type != TokenType.word) return false;
    final String l = t.lower;
    if (_units.containsKey(l)) return true;
    if (_ordinals.containsKey(l) || l == 'last' || l == 'middle' || l == 'any') {
      return _at(1).type == TokenType.word && _units.containsKey(_at(1).lower);
    }
    return false;
  }

  List<ChunkItem> _chunks() {
    final List<ChunkItem> out = <ChunkItem>[];
    while (_atChunkStart()) {
      out.add(_chunkItem());
      _expect('of');
    }
    return out;
  }

  ChunkItem _chunkItem() {
    final Token t = _next();
    final String l = t.lower;
    if (_ordinals.containsKey(l)) {
      return ChunkItem(_units[_next().lower]!,
          from: Literal(_ordinals[l]!.toDouble()));
    }
    if (l == 'last' || l == 'middle' || l == 'any') {
      return ChunkItem(_units[_next().lower]!, which: l);
    }
    final Expr from = _factor();
    final Expr? to = _accept('to') ? _factor() : null;
    return ChunkItem(_units[l]!, from: from, to: to);
  }

  // --------------------------------------------------------------- objects

  bool _atStackStart(int k) =>
      _isWord('stack', k) || (_isWord('this', k) && _isWord('stack', k + 1));

  bool _atCardStart(int k) =>
      _partKind(_at(k).lower) == 'card' || _isCardWithPrefix(k);

  bool _isCardWithPrefix(int k) {
    final Token t = _at(k);
    return t.type == TokenType.word &&
        (_ordinals.containsKey(t.lower) || _positions.contains(t.lower)) &&
        _partKind(_at(k + 1).lower) == 'card';
  }

  bool _atObjectStart() {
    final Token t = _cur;
    if (t.type != TokenType.word) return false;
    final String l = t.lower;
    if (l == 'me' || l == 'target' || l == 'whetstone') return true;
    if (_partKind(l) != null) return true;
    if (_atStackStart(0)) return true;
    return _isOrdinalPart(0, 'card') ||
        _isOrdinalPart(0, 'field') ||
        _isOrdinalPart(0, 'button');
  }

  PartRef _cardRef() {
    final Token t = _cur;
    final ObjectRef r = _objectRef();
    if (r is! PartRef || r.kind != 'card') {
      throw _err('expected a card but found $t', t);
    }
    return r;
  }

  StackRef _stackRef() {
    final bool thisStack = _accept('this');
    _expect('stack');
    if (thisStack) return const StackRef();
    if (_atFactorStart()) return StackRef(name: _factor());
    return const StackRef();
  }

  bool _atFactorStart() {
    final Token t = _cur;
    switch (t.type) {
      case TokenType.string:
      case TokenType.number:
        return true;
      case TokenType.symbol:
        return t.text == '(';
      case TokenType.word:
        return !_reserved.contains(t.lower) || t.lower == 'the';
      default:
        return false;
    }
  }

  ObjectRef _objectRef() {
    final Token t = _cur;
    if (t.type != TokenType.word) throw _err('expected an object but found $t');
    final String l = t.lower;

    if (l == 'me') {
      _next();
      return const MeRef();
    }
    if (l == 'target') {
      _next();
      return const TargetRef();
    }
    if (l == 'whetstone') {
      _next();
      return const AppRef();
    }
    if (_atStackStart(0)) return _stackRef();

    // first card / next card / this card / last field ...
    if ((_ordinals.containsKey(l) || _positions.contains(l)) &&
        _partKind(_at(1).lower) != null) {
      _next();
      final String kind = _partKind(_next().lower)!;
      if (_ordinals.containsKey(l)) {
        return _finishPart(kind, value: Literal(_ordinals[l]!.toDouble()));
      }
      return _finishPart(kind, position: l == 'previous' ? 'prev' : l);
    }

    final String? kind = _partKind(l);
    if (kind != null) {
      _next();
      if (_accept('id')) return _finishPart(kind, id: _factor());
      if (_cur.type == TokenType.word && _ordinals.containsKey(_cur.lower)) {
        return _finishPart(kind,
            value: Literal(_ordinals[_next().lower]!.toDouble()));
      }
      return _finishPart(kind, value: _factor());
    }
    throw _err('expected an object but found $t');
  }

  PartRef _finishPart(String kind, {Expr? value, Expr? id, String? position}) {
    ObjectRef? owner;
    if (_isWord('of')) {
      if (kind == 'card' && _atStackStart(1)) {
        _next();
        owner = _stackRef();
      } else if (kind != 'card' && _atCardStart(1)) {
        _next();
        owner = _cardRef();
      }
    }
    return PartRef(kind, value: value, id: id, position: position, owner: owner);
  }

  // ----------------------------------------------------------- expressions

  Expr _expr() => _or();

  Expr _or() {
    Expr l = _and();
    while (_accept('or')) {
      l = Binary('or', l, _and());
    }
    return l;
  }

  Expr _and() {
    Expr l = _equality();
    while (_accept('and')) {
      l = Binary('and', l, _equality());
    }
    return l;
  }

  Expr _equality() {
    Expr l = _relational();
    while (true) {
      if (_acceptSym('=')) {
        l = Binary('=', l, _relational());
      } else if (_acceptSym('<>')) {
        l = Binary('<>', l, _relational());
      } else if (_isWord('is')) {
        _next();
        final bool neg = _accept('not');
        final Expr r = _relational();
        l = Binary(neg ? '<>' : '=', l, r);
      } else {
        return l;
      }
    }
  }

  Expr _relational() {
    Expr l = _concat();
    while (true) {
      String? op;
      if (_isSym('<') || _isSym('>') || _isSym('<=') || _isSym('>=')) {
        op = _next().text;
      } else if (_isWord('contains')) {
        _next();
        op = 'contains';
      }
      if (op != null) {
        l = Binary(op, l, _concat());
        continue;
      }
      if (!_isWord('is')) return l;

      // is [not] in | a | an | newer than | older than
      final bool neg = _isWord('not', 1);
      final int k = neg ? 2 : 1;
      final Token w = _at(k);
      if (w.isWord('in')) {
        _p += k + 1;
        final Expr node = Binary('in', l, _concat());
        l = neg ? Unary('not', node) : node;
      } else if (w.isWord('a') || w.isWord('an')) {
        _p += k + 1;
        final Token typeTok = _cur;
        if (typeTok.type != TokenType.word) {
          throw _err('expected a type name but found $typeTok');
        }
        _next();
        l = TypeTest(l, typeTok.lower, neg);
      } else if (w.isWord('newer') || w.isWord('older')) {
        _p += k + 1;
        _expect('than');
        l = VersionCompare(l, _concat(),
            newer: w.isWord('newer'), negated: neg);
      } else {
        return l;
      }
    }
  }

  Expr _concat() {
    Expr l = _additive();
    while (_isSym('&') || _isSym('&&')) {
      l = Binary(_next().text, l, _additive());
    }
    return l;
  }

  Expr _additive() {
    Expr l = _multiplicative();
    while (_isSym('+') || _isSym('-')) {
      l = Binary(_next().text, l, _multiplicative());
    }
    return l;
  }

  Expr _multiplicative() {
    Expr l = _power();
    while (true) {
      if (_isSym('*') || _isSym('/')) {
        l = Binary(_next().text, l, _power());
      } else if (_isWord('div') || _isWord('mod')) {
        l = Binary(_next().lower, l, _power());
      } else {
        return l;
      }
    }
  }

  Expr _power() {
    Expr l = _unary();
    while (_acceptSym('^')) {
      l = Binary('^', l, _unary());
    }
    return l;
  }

  Expr _unary() {
    if (_acceptSym('-')) return Unary('-', _unary());
    if (_accept('not')) return Unary('not', _unary());
    if (_isWord('there') && _isWord('is', 1)) {
      _next();
      _next();
      final bool exists;
      if (_accept('no')) {
        exists = false;
      } else if (_accept('a') || _accept('an')) {
        exists = true;
      } else {
        throw _err("expected 'a', 'an' or 'no' but found $_cur");
      }
      return ThereIs(_objectRef(), exists: exists);
    }
    return _primary();
  }

  Expr _primary() {
    if (_atChunkStart()) {
      final List<ChunkItem> chunks = _chunks();
      return ChunkExpr(chunks, _factor());
    }
    return _factor();
  }

  Expr _factor() {
    final Token t = _cur;
    switch (t.type) {
      case TokenType.string:
        _next();
        return Literal(t.text);
      case TokenType.number:
        _next();
        final String text = t.text.endsWith('.') ? '${t.text}0' : t.text;
        return Literal(double.parse(text));
      case TokenType.symbol:
        if (t.text == '(') {
          _next();
          final Expr e = _expr();
          _expectSym(')');
          return e;
        }
        throw _err('unexpected $t');
      case TokenType.word:
        return _wordFactor(t);
      default:
        throw _err('unexpected $t');
    }
  }

  Expr _wordFactor(Token t) {
    final String l = t.lower;

    switch (l) {
      case 'empty':
        _next();
        return const Literal('');
      case 'true':
        _next();
        return const Literal(true);
      case 'false':
        _next();
        return const Literal(false);
      case 'return':
      case 'linefeed':
        _next();
        return const Literal('\n');
      case 'quote':
        _next();
        return const Literal('"');
      case 'space':
        _next();
        return const Literal(' ');
      case 'tab':
        _next();
        return const Literal('\t');
      case 'pi':
        _next();
        return const Literal(math.pi);
      case 'up':
      case 'down':
        _next();
        return Literal(l);
      case 'the':
        return _theForm();
      case 'msg':
      case 'message':
        _next();
        return const MsgRef();
      case 'selection':
        _next();
        return const SelectionRef();
    }

    if (_atObjectStart()) return _objectRef();

    // number of cards ...   (without 'the')
    if (l == 'number' && _isWord('of', 1) && _plurals.containsKey(_at(2).lower)) {
      _next();
      _next();
      return _numberOf();
    }
    // name of card 3     (without 'the')
    if (_properties.contains(l) && _isWord('of', 1)) {
      _next();
      _next();
      return PropertyRef(l, _propertyTarget());
    }
    // length of x   /  max(a, b)  /  clamp(1, 2, 3)
    if (_theFunctions.contains(l) && _isWord('of', 1)) {
      _next();
      _next();
      return FuncCall(t.text, <Expr>[_factor()]);
    }
    if (_isSym('(', 1) && (!_reserved.contains(l) || _theFunctions.contains(l))) {
      _next();
      return FuncCall(t.text, _callArgs());
    }

    if (_reserved.contains(l)) throw _err('unexpected $t');
    _next();
    return Variable(t.text);
  }

  List<Expr> _callArgs() {
    _expectSym('(');
    final List<Expr> args = <Expr>[];
    if (!_isSym(')')) {
      args.add(_expr());
      while (_acceptSym(',')) {
        args.add(_expr());
      }
    }
    _expectSym(')');
    return args;
  }

  /// After `the`.
  Expr _theForm() {
    _next(); // the
    final Token t = _cur;
    if (t.type != TokenType.word) throw _err("unexpected $t after 'the'");
    String l = t.lower;

    String? adjective;
    if ((l == 'long' || l == 'short' || l == 'abbrev') &&
        _at(1).type == TokenType.word &&
        _theFunctions.contains(_at(1).lower)) {
      adjective = l;
      _next();
      l = _cur.lower;
    }
    final Token nameTok = _cur;

    if (l == 'number' && _isWord('of', 1) && _plurals.containsKey(_at(2).lower)) {
      _next();
      _next();
      return _numberOf();
    }
    if (_properties.contains(l) && _isWord('of', 1)) {
      _next();
      _next();
      return PropertyRef(l, _propertyTarget());
    }
    if (_theFunctions.contains(l)) {
      _next();
      if (_accept('of')) {
        return FuncCall(nameTok.text, <Expr>[_factor()], adjective: adjective);
      }
      return FuncCall(nameTok.text, const <Expr>[], adjective: adjective);
    }
    throw _err("unknown form 'the ${nameTok.text}'", nameTok);
  }

  /// After `number of`; the current token is a plural word.
  Expr _numberOf() {
    final String what = _plurals[_next().lower]!;
    switch (what) {
      case 'cards':
        if (_isWord('of') && _atStackStart(1)) {
          _next();
          return NumberOf(what, scope: _stackRef());
        }
        return NumberOf(what);
      case 'fields':
      case 'buttons':
        if (_isWord('of') && _atCardStart(1)) {
          _next();
          return NumberOf(what, scope: _cardRef());
        }
        return NumberOf(what);
      default:
        _expect('in');
        return NumberOf(what, source: _factor());
    }
  }
}
