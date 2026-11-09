/// Tree-walking interpreter for Speakeasy base.
///
/// A [Runtime] is created over the application's root [HostObject]
/// (the `app`). It keeps the navigation state (current stack and card, and
/// the substack being viewed, if any), runs messages along the path
/// button -> card -> stack -> app, and talks to the user only through [Io].
///
/// Nothing here imports Flutter.
library;

import 'dart:math' as math;

import 'ast.dart';
import 'errors.dart';
import 'host.dart';
import 'parser.dart';
import 'values.dart';

/// What scripts can ask of the user interface. The defaults do nothing, so a
/// Runtime works headless (tests, batch runs). Whetstone overrides these.
class Io {
  const Io();

  /// `ask`: returns the reply, or null if the user cancelled.
  Future<String?> ask(String prompt, String defaultAnswer) async => null;

  /// `answer`: returns the label of the button chosen.
  Future<String> answer(String message, List<String> buttons) async =>
      buttons.isEmpty ? 'OK' : buttons.first;

  void beep(int count) {}

  Future<void> wait(Duration duration) async {}

  /// `save`: persist this card. May take a while (e.g. a network call).
  Future<void> save(HostObject card) async {}

  void showMessageBox(bool show) {}
}

/// An ordered set of references to cards, with a cursor, made by
/// `find cards where ...`. It holds the cards themselves (never copies);
/// removing one with `drop` leaves the real card alone.
class SubStack {
  SubStack(this.name, this.cards, this.scores);

  final String name;
  final List<HostObject> cards;

  /// Relevance of each card, set by `find`. The `score` property reads this.
  final Map<HostObject, double> scores;

  int cursor = 0;

  HostObject? get current {
    if (cards.isEmpty) return null;
    if (cursor < 0) return cards.first;
    if (cursor >= cards.length) return cards.last;
    return cards[cursor];
  }

  /// Removes [card]; true if it was there. The cursor keeps pointing at the
  /// same card, or at the next one if the cursor card was removed.
  bool remove(HostObject card) {
    final int i = cards.indexOf(card);
    if (i < 0) return false;
    cards.removeAt(i);
    scores.remove(card);
    if (i < cursor) cursor--;
    if (cursor >= cards.length) cursor = cards.isEmpty ? 0 : cards.length - 1;
    if (cursor < 0) cursor = 0;
    return true;
  }
}

// Control-flow signals. Thrown by statements and caught by the construct
// they leave; never visible to callers of [Runtime].
class _Return implements Exception {
  _Return(this.value);
  final Object? value;
}

class _ExitHandler implements Exception {}

class _ExitRepeat implements Exception {}

class _NextRepeat implements Exception {}

class _Pass implements Exception {}

class _Frame {
  _Frame(this.me, this.target, this.name, this.args);

  /// The object whose script is running.
  final HostObject me;

  /// The object the message was first sent to.
  final HostObject target;
  final String name;
  final List<Object?> args;
  final Map<String, Object?> vars = <String, Object?>{};
  final Set<String> globalNames = <String>{};
}

class _Cached {
  _Cached(this.source, this.script);
  final String source;
  final Script script;
}

class _View {
  _View.real(this.stack) : sub = null;
  _View.sub(SubStack this.sub) : stack = null;
  final HostObject? stack;
  final SubStack? sub;
}

class _RChunk {
  const _RChunk(this.unit, this.from, this.to, this.which);
  final String unit;
  final int? from;
  final int? to;
  final String? which;
}

const List<String> _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];
const List<String> _days = <String>[
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

class Runtime {
  Runtime(
    this.root, {
    this.io = const Io(),
    this.maxSteps = 1000000,
    DateTime Function()? clock,
    math.Random? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? math.Random() {
    currentStack = _firstChildOfKind(root, 'stack');
    currentCard = currentStack == null ? null : _firstChildOfKind(currentStack!, 'card');
  }

  /// The application object (top of the message path).
  final HostObject root;
  Io io;

  /// A script that runs more than this many statements is stopped.
  final int maxSteps;

  final DateTime Function() _clock;
  final math.Random _random;

  /// The message box text (`msg`).
  String msg = '';

  /// `the result`.
  Object? result = '';

  /// `itemDelimiter` (set it with `set the itemDelimiter of Whetstone to ";"`).
  String itemDelimiter = ',';

  HostObject? currentStack;
  HostObject? currentCard;

  /// The substack being viewed, or null when viewing the real stack.
  SubStack? substack;

  /// Substacks by lower-case name.
  final Map<String, SubStack> substacks = <String, SubStack>{};

  /// Called (at most once per wait, ask, answer or run) after a script
  /// changed something the UI may show.
  void Function()? onChange;

  final Map<String, Object?> _globals = <String, Object?>{};
  final Expando<_Cached> _cache = Expando<_Cached>('scripts');
  int _steps = 0;
  int _depth = 0;
  bool _dirty = false;

  // ------------------------------------------------------------ public API

  /// Runs [source] (statements, as typed in the message box).
  /// [me] defaults to the current card.
  Future<void> run(String source, {HostObject? me}) async {
    final HostObject owner = me ?? currentCard ?? root;
    final List<Stmt> body = Parser.parseStatements(source);
    _steps = 0;
    try {
      await _exec(body, _Frame(owner, owner, 'message box', const <Object?>[]));
    } on _Return {
      // fine at top level
    } on _ExitHandler {
      // fine
    } on _Pass {
      // fine
    } finally {
      _flush();
    }
  }

  /// Sends [message] to [target] along the message path. Does nothing if no
  /// handler is found.
  Future<void> send(String message, HostObject target,
      [List<Object?> args = const <Object?>[]]) async {
    _steps = 0;
    try {
      await _deliver(message, target, target, args);
    } finally {
      _flush();
    }
  }

  /// Evaluates one expression, e.g. `the number of cards`.
  Future<Object?> evaluate(String expression, {HostObject? me}) async {
    final HostObject owner = me ?? currentCard ?? root;
    _steps = 0;
    final Object? v = await _evalSource(
        expression, _Frame(owner, owner, 'message box', const <Object?>[]));
    _flush();
    return v;
  }

  /// Moves to [card] (leaves the substack view if the card is not in it).
  void goToCard(HostObject card) => _goCard(card);

  // ---------------------------------------------------------- bookkeeping

  void _touch() => _dirty = true;

  void _flush() {
    if (_dirty) {
      _dirty = false;
      onChange?.call();
    }
  }

  void _tick() {
    if (++_steps > maxSteps) {
      throw ScriptError('script ran too long (over $maxSteps steps)');
    }
  }

  static HostObject? _firstChildOfKind(HostObject o, String kind) {
    for (final HostObject c in o.children) {
      if (c.kind == kind) return c;
    }
    return null;
  }

  List<HostObject> _cardsOf(HostObject? stack) => stack == null
      ? <HostObject>[]
      : <HostObject>[
          for (final HostObject c in stack.children)
            if (c.kind == 'card') c
        ];

  _View _currentView() =>
      substack != null ? _View.sub(substack!) : _View.real(currentStack);

  List<HostObject> _viewCards(_View v) => v.sub?.cards ?? _cardsOf(v.stack);

  // ------------------------------------------------------------- scripts

  Script? _scriptOf(HostObject o) {
    final String src = o.script;
    if (src.trim().isEmpty) return null;
    final _Cached? c = _cache[o];
    if (c != null && c.source == src) return c.script;
    try {
      final Script s = Parser.parseScript(src);
      _cache[o] = _Cached(src, s);
      return s;
    } on ParseError catch (e) {
      throw ScriptError(
          'script of ${o.kind} "${o.name}", line ${e.line}: ${e.message}');
    }
  }

  (HostObject, Handler)? _findHandler(HostObject start, String name,
      {required bool function}) {
    for (HostObject? o = start; o != null; o = o.parent) {
      final Handler? h = _scriptOf(o)?.find(name, function: function);
      if (h != null) return (o, h);
    }
    return null;
  }

  /// Delivers a message from [start] up the path. True if a handler ran.
  Future<bool> _deliver(String message, HostObject start, HostObject target,
      List<Object?> args) async {
    bool found = false;
    for (HostObject? o = start; o != null; o = o.parent) {
      final Handler? h = _scriptOf(o)?.find(message, function: false);
      if (h == null) continue;
      found = true;
      final bool passed = await _runHandler(h, o, target, args);
      if (!passed) return true;
    }
    return found;
  }

  void _bindParams(Handler h, _Frame f, List<Object?> args) {
    for (int i = 0; i < h.params.length; i++) {
      f.vars[h.params[i].toLowerCase()] = i < args.length ? args[i] : '';
    }
  }

  /// Runs a message handler. Returns true if it executed `pass`.
  Future<bool> _runHandler(
      Handler h, HostObject owner, HostObject target, List<Object?> args) async {
    if (++_depth > 100) {
      _depth--;
      throw ScriptError('handlers are nested too deeply (over 100)');
    }
    final _Frame f = _Frame(owner, target, h.name, args);
    _bindParams(h, f, args);
    try {
      await _exec(h.body, f);
    } on _Return {
      // done
    } on _ExitHandler {
      // done
    } on _Pass {
      return true;
    } finally {
      _depth--;
    }
    return false;
  }

  Future<Object?> _callUser(
      Handler h, HostObject owner, HostObject target, List<Object?> args) async {
    if (++_depth > 100) {
      _depth--;
      throw ScriptError('functions are nested too deeply (over 100)');
    }
    final _Frame f = _Frame(owner, target, h.name, args);
    _bindParams(h, f, args);
    try {
      await _exec(h.body, f);
    } on _Return catch (r) {
      return r.value;
    } on _ExitHandler {
      // falls out with ''
    } on _Pass {
      // ignored in a function
    } finally {
      _depth--;
    }
    return '';
  }

  Future<Object?> _evalSource(String source, _Frame f) async {
    final List<Stmt> s = Parser.parseStatements('get $source');
    if (s.length != 1 || s.first is! Get) {
      throw ScriptError('"$source" is not an expression');
    }
    return _eval((s.first as Get).value, f);
  }

  // ----------------------------------------------------------- variables

  Object? _getVar(String name, _Frame f) {
    final String k = name.toLowerCase();
    if (f.globalNames.contains(k)) return _globals[k] ?? '';
    if (f.vars.containsKey(k)) return f.vars[k];
    if (k == 'it') return '';
    throw ScriptError("unknown variable '$name'");
  }

  void _setVar(String name, Object? value, _Frame f) {
    final String k = name.toLowerCase();
    if (f.globalNames.contains(k)) {
      _globals[k] = value;
    } else {
      f.vars[k] = value;
    }
  }

  // ---------------------------------------------------------- statements

  Future<void> _exec(List<Stmt> body, _Frame f) async {
    for (final Stmt s in body) {
      await _stmt(s, f);
    }
  }

  Future<void> _stmt(Stmt s, _Frame f) async {
    _tick();
    try {
      await _stmtInner(s, f);
    } on ScriptError catch (e) {
      if (e.line != null) rethrow;
      throw ScriptError(e.message, line: s.line);
    } on ArgumentError catch (e) {
      throw ScriptError('${e.message}', line: s.line);
    }
  }

  Future<void> _stmtInner(Stmt s, _Frame f) async {
    switch (s) {
      case Put p:
        await _put(p, f);
      case Get g:
        _setVar('it', await _eval(g.value, f), f);
      case SetProp p:
        await _setProp(p, f);
      case Arith a:
        await _arith(a, f);
      case Go g:
        final ObjectRef t = g.target;
        if (t is StackRef) {
          await _goStack(t, f);
        } else {
          _goCard(await _resolveCard(t as PartRef, f));
        }
      case FindCards c:
        await _findCards(c, f);
      case FindText t:
        await _findText(t, f);
      case Drop d:
        await _drop(d, f);
      case Sort so:
        await _sort(so, f);
      case Create c:
        await _create(c, f);
      case DeleteObject d:
        await _deleteObject(d, f);
      case DeleteText d:
        await _deleteText(d, f);
      case Save _:
        final HostObject? c = currentCard;
        if (c != null) await io.save(c);
      case ShowHide sh:
        (await _resolve(sh.target, f)).setProperty('visible', sh.show);
        _touch();
      case ShowHideMsgBox sh:
        io.showMessageBox(sh.show);
      case Answer a:
        final String text = toStr(await _eval(a.message, f));
        final List<String> labels = <String>[
          for (final Expr b in a.buttons) toStr(await _eval(b, f))
        ];
        _flush();
        _setVar('it', await io.answer(text, labels), f);
      case Ask a:
        final String prompt = toStr(await _eval(a.prompt, f));
        final String def =
            a.defaultAnswer == null ? '' : toStr(await _eval(a.defaultAnswer!, f));
        _flush();
        final String? reply = await io.ask(prompt, def);
        _setVar('it', reply ?? '', f);
        result = reply == null ? 'Cancel' : '';
      case Beep b:
        final int n = b.count == null ? 1 : toNum(await _eval(b.count!, f)).floor();
        io.beep(n < 1 ? 1 : n);
      case Wait w:
        await _wait(w, f);
      case Do d:
        await _exec(Parser.parseStatements(toStr(await _eval(d.source, f))), f);
      case ExitRepeat _:
        throw _ExitRepeat();
      case ExitHandler _:
        throw _ExitHandler();
      case NextRepeat _:
        throw _NextRepeat();
      case Global g:
        for (final String n in g.names) {
          final String k = n.toLowerCase();
          f.globalNames.add(k);
          _globals.putIfAbsent(k, () => '');
        }
      case Pass _:
        throw _Pass();
      case Return r:
        throw _Return(r.value == null ? '' : await _eval(r.value!, f));
      case Send se:
        final String message = toStr(await _eval(se.message, f));
        final HostObject target = await _resolve(se.target, f);
        await _deliver(message, target, target, const <Object?>[]);
      case MessageSend m:
        final List<Object?> args = <Object?>[
          for (final Expr a in m.args) await _eval(a, f)
        ];
        if (!await _deliver(m.name, f.me, f.target, args)) {
          throw ScriptError("no handler for '${m.name}'");
        }
      case If i:
        if (toBool(await _eval(i.cond, f))) {
          await _exec(i.thenBody, f);
        } else {
          await _exec(i.elseBody, f);
        }
      case Repeat r:
        await _repeat(r, f);
    }
  }

  Future<void> _repeat(Repeat r, _Frame f) async {
    /// Runs the body once. Returns false if the loop should end.
    Future<bool> once() async {
      _tick();
      try {
        await _exec(r.body, f);
      } on _NextRepeat {
        // go on with the next pass
      } on _ExitRepeat {
        return false;
      }
      return true;
    }

    switch (r.kind) {
      case 'forever':
        while (await once()) {}
      case 'until':
        while (!toBool(await _eval(r.cond!, f))) {
          if (!await once()) break;
        }
      case 'while':
        while (toBool(await _eval(r.cond!, f))) {
          if (!await once()) break;
        }
      case 'times':
        final int n = toNum(await _eval(r.count!, f)).floor();
        for (int i = 0; i < n; i++) {
          if (!await once()) break;
        }
      case 'with':
        final double from = toNum(await _eval(r.from!, f));
        final double to = toNum(await _eval(r.to!, f));
        for (double i = from; r.down ? i >= to : i <= to; i += r.down ? -1 : 1) {
          _setVar(r.variable!, i, f);
          if (!await once()) break;
        }
    }
  }

  Future<void> _wait(Wait w, _Frame f) async {
    _flush();
    if (w.kind == 'time') {
      final double amount = toNum(await _eval(w.amount!, f));
      final double ms = w.unit == 'seconds' ? amount * 1000 : amount * 1000 / 60;
      await io.wait(Duration(milliseconds: ms.round()));
      return;
    }
    while (true) {
      final bool c = toBool(await _eval(w.cond!, f));
      if (w.kind == 'until' ? c : !c) return;
      _tick();
      await io.wait(const Duration(milliseconds: 16));
    }
  }

  // -------------------------------------------------- containers and text

  Future<List<_RChunk>> _resolveChunks(List<ChunkItem> items, _Frame f) async {
    final List<_RChunk> out = <_RChunk>[];
    for (final ChunkItem i in items) {
      final int? from = i.from == null ? null : toNum(await _eval(i.from!, f)).floor();
      final int? to = i.to == null ? null : toNum(await _eval(i.to!, f)).floor();
      out.add(_RChunk(i.unit, from, to, i.which));
    }
    return out;
  }

  List<(int, int)> _unitSpans(String s, int lo, int hi, String unit) {
    final List<(int, int)> out = <(int, int)>[];
    switch (unit) {
      case 'char':
        for (int i = lo; i < hi; i++) {
          out.add((i, i + 1));
        }
      case 'word':
        for (final RegExpMatch m in RegExp(r'\S+').allMatches(s.substring(lo, hi))) {
          out.add((lo + m.start, lo + m.end));
        }
      case 'item':
        _splitSpans(s, lo, hi, itemDelimiter, out);
      case 'line':
        _splitSpans(s, lo, hi, '\n', out);
    }
    return out;
  }

  void _splitSpans(String s, int lo, int hi, String d, List<(int, int)> out) {
    if (d.isEmpty) {
      out.add((lo, hi));
      return;
    }
    int start = lo;
    while (true) {
      final int idx = s.indexOf(d, start);
      if (idx < 0 || idx + d.length > hi) {
        out.add((start, hi));
        return;
      }
      out.add((start, idx));
      start = idx + d.length;
    }
  }

  /// The (start, end) of the chunk in [s], or null if it does not exist.
  /// [chunks] are in written order, so the last one is applied first.
  (int, int)? _chunkSpan(String s, List<_RChunk> chunks) {
    int lo = 0;
    int hi = s.length;
    for (int k = chunks.length - 1; k >= 0; k--) {
      final _RChunk c = chunks[k];
      final List<(int, int)> spans = _unitSpans(s, lo, hi, c.unit);
      final int n = spans.length;
      if (n == 0) return null;
      int a;
      int b;
      if (c.which == 'last') {
        a = b = n;
      } else if (c.which == 'middle') {
        a = b = (n + 1) ~/ 2;
      } else if (c.which == 'any') {
        a = b = _random.nextInt(n) + 1;
      } else {
        a = c.from!;
        b = c.to ?? a;
      }
      if (a < 1 || a > n) return null;
      if (b > n) b = n;
      if (b < a) b = a;
      lo = spans[a - 1].$1;
      hi = spans[b - 1].$2;
    }
    return (lo, hi);
  }

  String _readChunks(String s, List<_RChunk> chunks) {
    final (int, int)? span = _chunkSpan(s, chunks);
    return span == null ? '' : s.substring(span.$1, span.$2);
  }

  String _putChunk(String old, List<_RChunk> chunks, String value, String mode) {
    final (int, int)? span = _chunkSpan(old, chunks);
    if (span == null) {
      final _RChunk c = chunks.last;
      if (chunks.length == 1 &&
          (c.unit == 'item' || c.unit == 'line') &&
          c.from != null) {
        final String d = c.unit == 'line' ? '\n' : itemDelimiter;
        final int n = _unitSpans(old, 0, old.length, c.unit).length;
        final int missing = c.from! - n;
        if (missing > 0) return old + d * missing + value;
      }
      throw ScriptError('there is no such ${c.unit} to put into');
    }
    switch (mode) {
      case 'before':
        return old.replaceRange(span.$1, span.$1, value);
      case 'after':
        return old.replaceRange(span.$2, span.$2, value);
      default:
        return old.replaceRange(span.$1, span.$2, value);
    }
  }

  Future<String> _readBase(Expr base, _Frame f, {bool create = false}) async {
    switch (base) {
      case Variable v:
        final String k = v.name.toLowerCase();
        if (create &&
            !f.globalNames.contains(k) &&
            !f.vars.containsKey(k)) {
          return '';
        }
        return toStr(_getVar(v.name, f));
      case MsgRef _:
        return msg;
      case PartRef p when p.kind == 'field':
        return toStr((await _resolve(p, f)).getProperty('text'));
      default:
        throw ScriptError('that is not a container');
    }
  }

  Future<void> _writeBase(Expr base, Object? value, _Frame f) async {
    switch (base) {
      case Variable v:
        _setVar(v.name, value, f);
      case MsgRef _:
        msg = toStr(value);
      case PartRef p when p.kind == 'field':
        (await _resolve(p, f)).setProperty('text', toStr(value));
      default:
        throw ScriptError('that is not a container');
    }
    _touch();
  }

  Future<void> _put(Put p, _Frame f) async {
    final Object? value = await _eval(p.value, f);
    final TextTarget? t = p.target;
    if (t == null) {
      msg = toStr(value);
      _touch();
      return;
    }
    final String mode = p.mode!;
    final List<_RChunk> chunks = await _resolveChunks(t.chunks, f);
    if (chunks.isEmpty) {
      if (mode == 'into') {
        await _writeBase(t.base, value, f);
      } else {
        final String old = await _readBase(t.base, f, create: true);
        await _writeBase(
            t.base, mode == 'before' ? toStr(value) + old : old + toStr(value), f);
      }
      return;
    }
    final String old = await _readBase(t.base, f, create: true);
    await _writeBase(t.base, _putChunk(old, chunks, toStr(value), mode), f);
  }

  Future<void> _arith(Arith a, _Frame f) async {
    final double operand = toNum(await _eval(a.value, f));
    final List<_RChunk> chunks = await _resolveChunks(a.target.chunks, f);
    final String old = await _readBase(a.target.base, f);
    final double cur = toNum(chunks.isEmpty ? old : _readChunks(old, chunks));
    final double r;
    switch (a.op) {
      case 'add':
        r = cur + operand;
      case 'subtract':
        r = cur - operand;
      case 'multiply':
        r = cur * operand;
      default:
        if (operand == 0) throw ScriptError('can\'t divide by zero');
        r = cur / operand;
    }
    if (chunks.isEmpty) {
      await _writeBase(a.target.base, r, f);
    } else {
      await _writeBase(
          a.target.base, _putChunk(old, chunks, formatNumber(r), 'into'), f);
    }
  }

  Future<void> _deleteText(DeleteText d, _Frame f) async {
    final List<_RChunk> chunks = await _resolveChunks(d.target.chunks, f);
    if (chunks.isEmpty) {
      await _writeBase(d.target.base, '', f);
      return;
    }
    final String old = await _readBase(d.target.base, f);
    final (int, int)? span = _chunkSpan(old, chunks);
    if (span == null) return;
    int a = span.$1;
    int b = span.$2;
    final _RChunk top = chunks.first;
    final String delim = top.unit == 'line'
        ? '\n'
        : top.unit == 'item'
            ? itemDelimiter
            : '';
    if (delim.isNotEmpty) {
      if (old.startsWith(delim, b)) {
        b += delim.length;
      } else if (a >= delim.length && old.startsWith(delim, a - delim.length)) {
        a -= delim.length;
      }
    }
    await _writeBase(d.target.base, old.replaceRange(a, b, ''), f);
  }

  // ------------------------------------------------------------- objects

  Future<_View> _resolveView(StackRef r, _Frame f) async {
    if (r.name == null) return _currentView();
    final String key = toStr(await _eval(r.name!, f));
    final SubStack? sub = substacks[key.toLowerCase()];
    if (sub != null) return _View.sub(sub);
    final HostObject? st = root.find('stack', key);
    if (st != null) return _View.real(st);
    throw ScriptError('there is no stack "$key"');
  }

  HostObject? _byName(List<HostObject> list, String name) {
    final String lower = name.toLowerCase();
    for (final HostObject o in list) {
      if (o.name.toLowerCase() == lower) return o;
    }
    return null;
  }

  Future<HostObject> _resolve(ObjectRef r, _Frame f) async {
    switch (r) {
      case MeRef _:
        return f.me;
      case TargetRef _:
        return f.target;
      case AppRef _:
        return root;
      case StackRef s:
        final _View v = await _resolveView(s, f);
        if (v.stack == null) {
          throw ScriptError('substack "${v.sub!.name}" is not an object');
        }
        return v.stack!;
      case PartRef p:
        return p.kind == 'card' ? _resolveCard(p, f) : _resolvePart(p, f);
    }
  }

  Future<HostObject> _resolveCard(PartRef p, _Frame f) async {
    final ObjectRef? owner = p.owner;
    final _View view =
        owner is StackRef ? await _resolveView(owner, f) : _currentView();
    final List<HostObject> cards = _viewCards(view);

    final String? pos = p.position;
    if (pos != null) {
      final HostObject? cur = currentCard;
      if (pos == 'this') {
        return cur ?? (throw ScriptError('there is no current card'));
      }
      if (cards.isEmpty) throw ScriptError('there are no cards');
      final int n = cards.length;
      final int idx = cur == null ? -1 : cards.indexOf(cur);
      switch (pos) {
        case 'next':
          return cards[(idx + 1) % n];
        case 'prev':
          return cards[idx - 1 < 0 ? n - 1 : idx - 1];
        case 'last':
          return cards.last;
        default:
          return cards[_random.nextInt(n)];
      }
    }

    final List<HostObject> real = _cardsOf(currentStack);
    if (p.id != null) {
      final String id = toStr(await _eval(p.id!, f));
      for (final HostObject c in <HostObject>[...cards, ...real]) {
        if (c.id == id) return c;
      }
      throw ScriptError('there is no card id $id');
    }

    final Object? v = await _eval(p.value!, f);
    if (v is double) return _atIndex(cards, v, 'card');
    final String name = toStr(v);
    final HostObject? byName = _byName(cards, name) ??
        (view.sub != null ? _byName(real, name) : null);
    if (byName != null) return byName;
    final double? asNumber = tryNum(v);
    if (asNumber != null) return _atIndex(cards, asNumber, 'card');
    throw ScriptError('there is no card "$name"');
  }

  HostObject _atIndex(List<HostObject> list, double d, String what) {
    final int i = d.floor();
    if (i < 1 || i > list.length) throw ScriptError('there is no $what $i');
    return list[i - 1];
  }

  Future<HostObject> _resolvePart(PartRef p, _Frame f) async {
    final ObjectRef? owner = p.owner;
    final HostObject card = owner == null
        ? (currentCard ?? (throw ScriptError('there is no current card')))
        : await _resolve(owner, f);
    final List<HostObject> parts = <HostObject>[
      for (final HostObject c in card.children)
        if (c.kind == p.kind) c
    ];
    final String? pos = p.position;
    if (pos != null) {
      if (parts.isEmpty) throw ScriptError('there are no ${p.kind}s on "${card.name}"');
      if (pos == 'last') return parts.last;
      if (pos == 'any') return parts[_random.nextInt(parts.length)];
      throw ScriptError("'$pos ${p.kind}' is not supported");
    }
    if (p.id != null) {
      final String id = toStr(await _eval(p.id!, f));
      for (final HostObject c in parts) {
        if (c.id == id) return c;
      }
      throw ScriptError('there is no ${p.kind} id $id on "${card.name}"');
    }
    final Object? v = await _eval(p.value!, f);
    if (v is double) return _atIndex(parts, v, p.kind);
    final String name = toStr(v);
    final HostObject? byName = _byName(parts, name);
    if (byName != null) return byName;
    final double? asNumber = tryNum(v);
    if (asNumber != null) return _atIndex(parts, asNumber, p.kind);
    throw ScriptError('there is no ${p.kind} "$name" on "${card.name}"');
  }

  /// What an object reference means used as a value.
  Future<Object?> _objectValue(ObjectRef r, _Frame f) async {
    if (r is PartRef && r.kind == 'field') {
      return toStr((await _resolve(r, f)).getProperty('text'));
    }
    String what = 'an object';
    try {
      final HostObject o = await _resolve(r, f);
      what = 'the ${o.kind} "${o.name}"';
    } on ScriptError {
      // keep the generic wording
    }
    throw ScriptError(
        '$what has no text value; ask for a field or a property, e.g. '
        'field "symptom" or "the name of ..."');
  }

  // ----------------------------------------------------------- navigation

  void _setCurrent(HostObject? card) {
    currentCard = card;
    final SubStack? s = substack;
    if (s != null && card != null) {
      final int i = s.cards.indexOf(card);
      if (i >= 0) s.cursor = i;
    }
    _touch();
  }

  void _goCard(HostObject card) {
    final SubStack? s = substack;
    if (s != null && !s.cards.contains(card)) substack = null;
    final HostObject? parent = card.parent;
    if (parent != null && parent.kind == 'stack') currentStack = parent;
    _setCurrent(card);
  }

  Future<void> _goStack(StackRef r, _Frame f) async {
    final _View v = await _resolveView(r, f);
    if (v.sub != null) {
      substack = v.sub;
      _setCurrent(v.sub!.current);
    } else {
      substack = null;
      currentStack = v.stack;
      final List<HostObject> cards = _cardsOf(v.stack);
      _setCurrent(cards.isEmpty ? null : cards.first);
    }
  }

  // ------------------------------------------------------------ substacks

  /// Runs [body] with `this card` set to [card], then restores it.
  Future<T> _withCard<T>(HostObject card, Future<T> Function() body) async {
    final HostObject? saved = currentCard;
    currentCard = card;
    try {
      return await body();
    } finally {
      currentCard = saved;
    }
  }

  Future<void> _findCards(FindCards c, _Frame f) async {
    final String name =
        c.into?.name == null ? 'found' : toStr(await _eval(c.into!.name!, f));
    final List<HostObject> hits = <HostObject>[];
    final Map<HostObject, double> scores = <HostObject, double>{};
    for (final HostObject card in _cardsOf(currentStack)) {
      final Object? v = await _withCard(card, () => _eval(c.where, f));
      double score;
      if (v is double) {
        score = v;
      } else {
        score = toBool(v) ? 1 : 0;
      }
      if (score > 0) {
        hits.add(card);
        scores[card] = score;
      }
    }
    // Highest score first; equal scores keep stack order.
    final Map<HostObject, int> order = <HostObject, int>{
      for (int i = 0; i < hits.length; i++) hits[i]: i
    };
    hits.sort((HostObject a, HostObject b) {
      final int byScore = scores[b]!.compareTo(scores[a]!);
      return byScore != 0 ? byScore : order[a]!.compareTo(order[b]!);
    });
    final SubStack sub = SubStack(name, hits, scores);
    substacks[name.toLowerCase()] = sub;
    if (substack != null && substack!.name.toLowerCase() == name.toLowerCase()) {
      substack = sub;
      _setCurrent(sub.current);
    }
    result = '';
    _touch();
  }

  Future<void> _findText(FindText t, _Frame f) async {
    final String needle = toStr(await _eval(t.text, f)).toLowerCase();
    String? fieldName;
    int? fieldIndex;
    final Expr? fv = t.field?.value;
    if (fv != null) {
      final Object? v = await _eval(fv, f);
      if (v is double) {
        fieldIndex = v.floor();
      } else {
        fieldName = toStr(v);
      }
    }
    final List<HostObject> cards = _viewCards(_currentView());
    final int n = cards.length;
    final HostObject? cur = currentCard;
    final int start = cur == null ? -1 : cards.indexOf(cur);
    for (int k = 1; k <= n; k++) {
      final HostObject card = cards[(start + k) % n];
      final List<HostObject> fields = <HostObject>[
        for (final HostObject c in card.children)
          if (c.kind == 'field') c
      ];
      List<HostObject> search = fields;
      if (fieldName != null) {
        final HostObject? one = _byName(fields, fieldName);
        search = one == null ? <HostObject>[] : <HostObject>[one];
      } else if (fieldIndex != null) {
        search = fieldIndex >= 1 && fieldIndex <= fields.length
            ? <HostObject>[fields[fieldIndex - 1]]
            : <HostObject>[];
      }
      for (final HostObject fld in search) {
        if (toStr(fld.getProperty('text')).toLowerCase().contains(needle)) {
          _goCard(card);
          result = '';
          return;
        }
      }
    }
    result = 'not found';
  }

  Future<void> _drop(Drop d, _Frame f) async {
    final ObjectRef? owner = d.card.owner;
    final SubStack? sub = owner is StackRef
        ? (await _resolveView(owner, f)).sub
        : substack;
    if (sub == null) {
      throw ScriptError(
          'drop works on a substack (use find cards where ... first); use delete to remove a card');
    }
    final HostObject card = await _resolveCard(d.card, f);
    if (!sub.remove(card)) {
      throw ScriptError('"${card.name}" is not in substack "${sub.name}"');
    }
    if (identical(sub, substack)) _setCurrent(sub.current);
    _touch();
  }

  Future<void> _sort(Sort s, _Frame f) async {
    final SubStack? sub = substack;
    if (sub == null) {
      throw ScriptError(
          'sort works on a substack; use find cards where ... and go to it first');
    }
    final HostObject? keep = sub.current;
    final List<(HostObject, Object?)> keyed = <(HostObject, Object?)>[];
    for (final HostObject c in sub.cards) {
      keyed.add((c, await _withCard(c, () => _eval(s.key, f))));
    }
    final Map<HostObject, int> order = <HostObject, int>{
      for (int i = 0; i < sub.cards.length; i++) sub.cards[i]: i
    };
    int compare(Object? a, Object? b) {
      switch (s.mode) {
        case 'numeric':
          return toNum(a).compareTo(toNum(b));
        case 'text':
          return toStr(a).toLowerCase().compareTo(toStr(b).toLowerCase());
        default:
          return compareValues(a, b);
      }
    }

    keyed.sort(((HostObject, Object?) a, (HostObject, Object?) b) {
      int c = compare(a.$2, b.$2);
      if (s.descending) c = -c;
      return c != 0 ? c : order[a.$1]!.compareTo(order[b.$1]!);
    });
    sub.cards
      ..clear()
      ..addAll(keyed.map(((HostObject, Object?) e) => e.$1));
    if (keep != null) sub.cursor = sub.cards.indexOf(keep);
    _touch();
  }

  // ---------------------------------------------------- create and delete

  Future<void> _create(Create c, _Frame f) async {
    final String name = c.name == null ? '' : toStr(await _eval(c.name!, f));
    if (c.kind == 'card') {
      final HostObject stack =
          currentStack ?? (throw ScriptError('there is no stack to put the card in'));
      final HostObject card = stack.createChild('card', name);
      substack = null;
      _setCurrent(card);
      return;
    }
    final HostObject card =
        currentCard ?? (throw ScriptError('there is no current card'));
    card.createChild(c.kind, name);
    _touch();
  }

  Future<void> _deleteObject(DeleteObject d, _Frame f) async {
    final HostObject obj = await _resolve(d.target, f);
    final HostObject parent =
        obj.parent ?? (throw ScriptError('can\'t delete the application'));
    final List<HostObject> before = _viewCards(_currentView());
    final int idx = before.indexOf(obj);
    parent.removeChild(obj);
    for (final SubStack s in substacks.values) {
      s.remove(obj);
    }
    if (obj.kind == 'card' && identical(currentCard, obj)) {
      final List<HostObject> after = _viewCards(_currentView());
      if (after.isEmpty) {
        currentCard = null;
      } else {
        currentCard = after[math.min(math.max(idx, 0), after.length - 1)];
      }
      _setCurrent(currentCard);
    }
    if (obj.kind == 'stack' && identical(currentStack, obj)) {
      currentStack = _firstChildOfKind(root, 'stack');
      substack = null;
      final List<HostObject> cards = _cardsOf(currentStack);
      _setCurrent(cards.isEmpty ? null : cards.first);
    }
    _touch();
  }

  // ------------------------------------------------------------ properties

  Object? _getProp(HostObject obj, String prop) {
    switch (prop) {
      case 'itemdelimiter':
        if (identical(obj, root)) return itemDelimiter;
        throw ScriptError('itemDelimiter belongs to Whetstone');
      case 'number':
        List<HostObject> siblings = <HostObject>[
          for (final HostObject c in obj.parent?.children ?? <HostObject>[])
            if (c.kind == obj.kind) c
        ];
        if (obj.kind == 'card') {
          final List<HostObject> view = _viewCards(_currentView());
          if (view.contains(obj)) siblings = view;
        }
        final int i = siblings.indexOf(obj);
        return (i < 0 ? 0 : i + 1).toDouble();
      case 'score':
        return substack?.scores[obj] ?? 0.0;
    }
    final Object? v = obj.getProperty(prop);
    return v is int ? v.toDouble() : v;
  }

  Future<void> _setProp(SetProp s, _Frame f) async {
    final Object? value = await _eval(s.value, f);
    final Expr t = s.target;
    if (t is ChunkExpr) {
      if (s.property != 'text') {
        throw ScriptError('only the text of a chunk can be set');
      }
      await _put(
          Put(s.line, Literal(toStr(value)), 'into', TextTarget(t.chunks, t.source)),
          f);
      return;
    }
    final HostObject obj = await _resolve(t as ObjectRef, f);
    switch (s.property) {
      case 'itemdelimiter':
        if (!identical(obj, root)) throw ScriptError('itemDelimiter belongs to Whetstone');
        itemDelimiter = toStr(value);
      case 'visible':
        obj.setProperty('visible', toBool(value));
      case 'name':
      case 'script':
      case 'text':
        obj.setProperty(s.property, toStr(value));
      default:
        obj.setProperty(s.property, value);
    }
    _touch();
  }

  // ------------------------------------------------------------ expressions

  Future<Object?> _eval(Expr e, _Frame f) async {
    _tick();
    switch (e) {
      case Literal l:
        return l.value;
      case Variable v:
        return _getVar(v.name, f);
      case Binary b:
        return _binary(b, f);
      case Unary u:
        final Object? x = await _eval(u.operand, f);
        return u.op == '-' ? -toNum(x) : !toBool(x);
      case TypeTest t:
        final Object? x = await _eval(t.operand, f);
        final bool r;
        switch (t.typeName) {
          case 'number':
            r = isNumeric(x);
          case 'integer':
            final double? d = tryNum(x);
            r = d != null && d == d.truncateToDouble();
          case 'logical':
            r = x is bool ||
                (x is String &&
                    (x.toLowerCase() == 'true' || x.toLowerCase() == 'false'));
          default:
            throw ScriptError("unknown type '${t.typeName}' (use number, integer or logical)");
        }
        return t.negated ? !r : r;
      case VersionCompare v:
        final int c = compareVersions(await _eval(v.left, f), await _eval(v.right, f));
        final bool r = v.newer ? c > 0 : c < 0;
        return v.negated ? !r : r;
      case ThereIs t:
        bool exists;
        try {
          await _resolve(t.target, f);
          exists = true;
        } on ScriptError {
          exists = false;
        }
        return t.exists ? exists : !exists;
      case ChunkExpr c:
        final String s = toStr(await _eval(c.source, f));
        return _readChunks(s, await _resolveChunks(c.chunks, f));
      case FuncCall c:
        return _function(c, f);
      case NumberOf n:
        return _numberOf(n, f);
      case PropertyRef p:
        final Expr t = p.target;
        if (t is ChunkExpr) {
          if (p.property != 'text') {
            throw ScriptError('only the text of a chunk can be read');
          }
          return _eval(t, f);
        }
        return _getProp(await _resolve(t as ObjectRef, f), p.property);
      case MsgRef _:
        return msg;
      case SelectionRef _:
        throw ScriptError('selection is not supported');
      case ObjectRef o:
        return _objectValue(o, f);
    }
  }

  Future<Object?> _binary(Binary b, _Frame f) async {
    if (b.op == 'or') {
      return toBool(await _eval(b.left, f)) || toBool(await _eval(b.right, f));
    }
    if (b.op == 'and') {
      return toBool(await _eval(b.left, f)) && toBool(await _eval(b.right, f));
    }
    final Object? l = await _eval(b.left, f);
    final Object? r = await _eval(b.right, f);
    switch (b.op) {
      case '=':
        return valuesEqual(l, r);
      case '<>':
        return !valuesEqual(l, r);
      case '<':
        return compareValues(l, r) < 0;
      case '>':
        return compareValues(l, r) > 0;
      case '<=':
        return compareValues(l, r) <= 0;
      case '>=':
        return compareValues(l, r) >= 0;
      case 'contains':
        return toStr(l).toLowerCase().contains(toStr(r).toLowerCase());
      case 'in':
        return toStr(r).toLowerCase().contains(toStr(l).toLowerCase());
      case '&':
        return toStr(l) + toStr(r);
      case '&&':
        return '${toStr(l)} ${toStr(r)}';
    }
    final double x = toNum(l);
    final double y = toNum(r);
    final double out;
    switch (b.op) {
      case '+':
        out = x + y;
      case '-':
        out = x - y;
      case '*':
        out = x * y;
      case '/':
        if (y == 0) throw ScriptError('can\'t divide by zero');
        out = x / y;
      case 'div':
        if (y == 0) throw ScriptError('can\'t divide by zero');
        out = (x / y).truncateToDouble();
      case 'mod':
        if (y == 0) throw ScriptError('can\'t divide by zero');
        out = x - y * (x / y).floorToDouble();
      case '^':
        out = math.pow(x, y).toDouble();
      default:
        throw ScriptError("unknown operator '${b.op}'");
    }
    if (out.isNaN || out.isInfinite) throw ScriptError('the result is not a number');
    return out;
  }

  Future<Object?> _numberOf(NumberOf n, _Frame f) async {
    switch (n.what) {
      case 'cards':
        final ObjectRef? scope = n.scope;
        final _View v = scope is StackRef ? await _resolveView(scope, f) : _currentView();
        return _viewCards(v).length.toDouble();
      case 'fields':
      case 'buttons':
        final ObjectRef? scope = n.scope;
        final HostObject card = scope == null
            ? (currentCard ?? (throw ScriptError('there is no current card')))
            : await _resolve(scope, f);
        final String kind = n.what == 'fields' ? 'field' : 'button';
        return card.children.where((HostObject c) => c.kind == kind).length.toDouble();
    }
    final String s = toStr(await _eval(n.source!, f));
    if (s.isEmpty) return 0.0;
    final String unit = const <String, String>{
      'chars': 'char',
      'words': 'word',
      'items': 'item',
      'lines': 'line',
    }[n.what]!;
    return _unitSpans(s, 0, s.length, unit).length.toDouble();
  }

  // ------------------------------------------------------------- functions

  List<double> _numList(List<Object?> args) {
    final List<double> out = <double>[];
    for (final Object? a in args) {
      if (a is String && a.contains(',')) {
        out.addAll(a.split(',').map(toNum));
      } else {
        out.add(toNum(a));
      }
    }
    if (out.isEmpty) throw ScriptError('expected at least one number');
    return out;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<Object?> _function(FuncCall c, _Frame f) async {
    final List<Object?> args = <Object?>[
      for (final Expr a in c.args) await _eval(a, f)
    ];
    final (HostObject, Handler)? user = _findHandler(f.me, c.name, function: true);
    if (user != null) return _callUser(user.$2, user.$1, f.target, args);

    Object? arg(int i) {
      if (i >= args.length) {
        throw ScriptError("'${c.name}' needs ${i + 1} value(s)");
      }
      return args[i];
    }

    switch (c.name.toLowerCase()) {
      case 'abs':
        return toNum(arg(0)).abs();
      case 'sqrt':
        final double x = toNum(arg(0));
        if (x < 0) throw ScriptError('can\'t take the square root of a negative number');
        return math.sqrt(x);
      case 'round':
        return toNum(arg(0)).roundToDouble();
      case 'trunc':
        return toNum(arg(0)).truncateToDouble();
      case 'sum':
        return _numList(args).fold<double>(0, (double a, double b) => a + b);
      case 'average':
        final List<double> l = _numList(args);
        return l.fold<double>(0, (double a, double b) => a + b) / l.length;
      case 'max':
        return _numList(args).reduce(math.max);
      case 'min':
        return _numList(args).reduce(math.min);
      case 'length':
        return toStr(arg(0)).length.toDouble();
      case 'offset':
        return (toStr(arg(1)).toLowerCase().indexOf(toStr(arg(0)).toLowerCase()) + 1)
            .toDouble();
      case 'random':
        final int n = toNum(arg(0)).floor();
        if (n < 1) throw ScriptError('random needs a number of 1 or more');
        return (_random.nextInt(n) + 1).toDouble();
      case 'value':
        return _evalSource(toStr(arg(0)), f);
      case 'result':
        return result;
      case 'target':
        return f.target.name;
      case 'param':
        final int i = toNum(arg(0)).floor();
        return i >= 1 && i <= f.args.length ? f.args[i - 1] : '';
      case 'paramcount':
        return f.args.length.toDouble();
      case 'params':
        return f.args.map(toStr).join(',');
      case 'date':
        final DateTime d = _clock();
        if (c.adjective == 'long') {
          return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
        }
        return '${d.year}-${_two(d.month)}-${_two(d.day)}';
      case 'time':
        final DateTime d = _clock();
        final String hm = '${_two(d.hour)}:${_two(d.minute)}';
        return c.adjective == 'long' ? '$hm:${_two(d.second)}' : hm;
      case 'seconds':
        return (_clock().millisecondsSinceEpoch ~/ 1000).toDouble();
      case 'ticks':
        return (_clock().millisecondsSinceEpoch * 60 ~/ 1000).toDouble();
    }
    throw ScriptError("unknown function '${c.name}'");
  }
}
