import 'dart:io';

import 'package:speakeasy/speakeasy.dart';
import 'package:test/test.dart';

List<Stmt> stmts(String s) => Parser.parseStatements(s);
Stmt one(String s) => stmts(s).single;

void main() {
  group('lexer', () {
    test('words, numbers, strings, symbols', () {
      final List<Token> t = tokenize('put 3.5 & "hi there" into x');
      expect(t.map((Token e) => e.text).toList(),
          <String>['put', '3.5', '&', 'hi there', 'into', 'x', '']);
      expect(t.last.type, TokenType.eof);
    });

    test('comments and continuation lines vanish', () {
      final List<Token> t = tokenize('put 1 -- note\nput 2 ¬\n  & 3');
      expect(t.where((Token e) => e.type == TokenType.newline).length, 1);
      expect(t.map((Token e) => e.text), contains('3'));
    });

    test('unicode comparison operators are normalised', () {
      final List<String> t =
          tokenize('a ≠ b ≤ c ≥ d').map((Token e) => e.text).toList();
      expect(t, containsAll(<String>['<>', '<=', '>=']));
    });

    test('unterminated string is an error', () {
      expect(() => tokenize('put "abc'), throwsA(isA<ParseError>()));
    });

    test('line numbers', () {
      final List<Token> t = tokenize('a\nb\n\nc');
      expect(t.firstWhere((Token e) => e.text == 'c').line, 4);
    });
  });

  group('statements', () {
    test('put into a field', () {
      final Put p = one('put "draft" into field "state"') as Put;
      expect(p.mode, 'into');
      final Expr base = p.target!.base;
      expect(base, isA<PartRef>());
      expect((base as PartRef).kind, 'field');
    });

    test('put with no target goes to the message box', () {
      final Put p = one('put 1 + 1') as Put;
      expect(p.target, isNull);
    });

    test('keywords are case-insensitive', () {
      expect(one('PUT "a" INTO msg'), isA<Put>());
    });

    test('go to next card', () {
      final Go g = one('go to next card') as Go;
      final PartRef c = g.target as PartRef;
      expect(c.kind, 'card');
      expect(c.position, 'next');
    });

    test('go to first card', () {
      final PartRef c = (one('go to first card') as Go).target as PartRef;
      expect((c.value as Literal).value, 1.0);
    });

    test('go to stack "hits"', () {
      final Go g = one('go to stack "hits"') as Go;
      expect(g.target, isA<StackRef>());
    });

    test('find cards where ... into stack', () {
      final FindCards f = one(
              'find cards where field "body" contains it into stack "hits"')
          as FindCards;
      expect((f.where as Binary).op, 'contains');
      expect(((f.into!.name) as Literal).value, 'hits');
    });

    test('find cards where without into', () {
      final FindCards f = one('find cards where true') as FindCards;
      expect(f.into, isNull);
    });

    test('find text in field', () {
      final FindText f = one('find it in field "body"') as FindText;
      expect(f.field!.kind, 'field');
    });

    test('drop this card', () {
      final Drop d = one('drop this card') as Drop;
      expect(d.card.position, 'this');
    });

    test('delete an object and delete text', () {
      expect(one('delete card 3'), isA<DeleteObject>());
      expect(one('delete line 1 of field "x"'), isA<DeleteText>());
      expect(one('delete x'), isA<DeleteText>());
    });

    test('create', () {
      final Create c = one('create card "Untitled"') as Create;
      expect(c.kind, 'card');
      expect(one('create button'), isA<Create>());
    });

    test('set a property', () {
      final SetProp s = one('set the name of card 2 to "x"') as SetProp;
      expect(s.property, 'name');
      expect(s.target, isA<PartRef>());
    });

    test('answer with up to three buttons', () {
      final Answer a = one('answer "Sure?" with "Yes" or "No" or "Maybe"')
          as Answer;
      expect(a.buttons.length, 3);
    });

    test('add, subtract, multiply, divide', () {
      expect((one('add 1 to n') as Arith).op, 'add');
      expect((one('subtract 1 from n') as Arith).op, 'subtract');
      expect((one('multiply n by 2') as Arith).op, 'multiply');
      expect((one('divide n by 2') as Arith).op, 'divide');
    });

    test('message send with arguments', () {
      final MessageSend m = one('clamp 1, 2, 3') as MessageSend;
      expect(m.name, 'clamp');
      expect(m.args.length, 3);
    });

    test('sort, wait, show, hide, beep, save', () {
      expect(one('sort cards descending numeric by field "score"'), isA<Sort>());
      expect(one('wait 30'), isA<Wait>());
      expect(one('wait until x'), isA<Wait>());
      expect(one('show msg box'), isA<ShowHideMsgBox>());
      expect(one('hide button "go"'), isA<ShowHide>());
      expect(one('beep 2'), isA<Beep>());
      expect(one('save'), isA<Save>());
    });
  });

  group('control flow', () {
    test('one-line if with else on the next line', () {
      final List<Stmt> s = stmts('if x then put 1 into y\nelse put 2 into y');
      final If i = s.single as If;
      expect(i.thenBody.length, 1);
      expect(i.elseBody.length, 1);
    });

    test('multi-line if / else / end if', () {
      final If i = one('if x then\n put 1 into y\nelse\n put 2 into y\nend if')
          as If;
      expect(i.thenBody.length, 1);
      expect(i.elseBody.length, 1);
    });

    test('then on the next line', () {
      expect(one('if x\nthen\n put 1 into y\nend if'), isA<If>());
    });

    test('repeat forms', () {
      expect((one('repeat 3 times\nbeep\nend repeat') as Repeat).kind, 'times');
      expect((one('repeat forever\nbeep\nend repeat') as Repeat).kind, 'forever');
      expect((one('repeat until x\nbeep\nend repeat') as Repeat).kind, 'until');
      expect((one('repeat while x\nbeep\nend repeat') as Repeat).kind, 'while');
      final Repeat r =
          one('repeat with i = 10 down to 1\nbeep\nend repeat') as Repeat;
      expect(r.kind, 'with');
      expect(r.down, isTrue);
      expect(r.variable, 'i');
    });

    test('exit and next repeat', () {
      expect(one('exit repeat'), isA<ExitRepeat>());
      expect(one('next repeat'), isA<NextRepeat>());
      expect(one('exit finish'), isA<ExitHandler>());
    });
  });

  group('expressions', () {
    Expr e(String src) => (one('get $src') as Get).value;

    test('precedence: * binds tighter than +', () {
      final Binary b = e('1 + 2 * 3') as Binary;
      expect(b.op, '+');
      expect((b.right as Binary).op, '*');
    });

    test('precedence: and binds tighter than or', () {
      final Binary b = e('a or b and c') as Binary;
      expect(b.op, 'or');
      expect((b.right as Binary).op, 'and');
    });

    test('is / is not become = and <>', () {
      expect((e('x is empty') as Binary).op, '=');
      expect((e('x is not empty') as Binary).op, '<>');
    });

    test('is in / is not in', () {
      expect((e('"a" is in x') as Binary).op, 'in');
      final Unary u = e('"a" is not in x') as Unary;
      expect(u.op, 'not');
    });

    test('is a number', () {
      final TypeTest t = e('x is a number') as TypeTest;
      expect(t.typeName, 'number');
      expect(t.negated, isFalse);
    });

    test('newer than / older than', () {
      final VersionCompare v = e('a is newer than b') as VersionCompare;
      expect(v.newer, isTrue);
      final VersionCompare w = e('a is not older than b') as VersionCompare;
      expect(w.newer, isFalse);
      expect(w.negated, isTrue);
    });

    test('concatenation', () {
      expect((e('"a" & "b"') as Binary).op, '&');
      expect((e('"a" && "b"') as Binary).op, '&&');
    });

    test('chunks', () {
      final ChunkExpr c = e('word 2 of line 1 of x') as ChunkExpr;
      expect(c.chunks.map((ChunkItem i) => i.unit).toList(),
          <String>['word', 'line']);
      final ChunkExpr last = e('last line of x') as ChunkExpr;
      expect(last.chunks.single.which, 'last');
      final ChunkExpr range = e('char 1 to 3 of x') as ChunkExpr;
      expect(range.chunks.single.to, isNotNull);
    });

    test('number of', () {
      expect((e('the number of cards') as NumberOf).what, 'cards');
      final NumberOf n = e('the number of cards of stack "hits"') as NumberOf;
      expect(n.scope, isA<StackRef>());
      expect((e('the number of words in x') as NumberOf).what, 'words');
      expect(e('number of fields'), isA<NumberOf>());
    });

    test('properties', () {
      final PropertyRef p = e('the name of this card') as PropertyRef;
      expect(p.property, 'name');
      expect(e('score of card 2'), isA<PropertyRef>());
      expect(e('the number of this card'), isA<PropertyRef>());
    });

    test('functions', () {
      expect(e('the date'), isA<FuncCall>());
      expect((e('the long date') as FuncCall).adjective, 'long');
      expect((e('the length of x') as FuncCall).args.length, 1);
      expect((e('max(1, 2, 3)') as FuncCall).args.length, 3);
      expect((e('clamp(1, 2, 3)') as FuncCall).name, 'clamp');
      expect(e('the result'), isA<FuncCall>());
    });

    test('constants', () {
      expect((e('empty') as Literal).value, '');
      expect((e('true') as Literal).value, true);
      expect((e('return') as Literal).value, '\n');
    });

    test('there is', () {
      expect((e('there is a card "x"') as ThereIs).exists, isTrue);
      expect((e('there is no field "x"') as ThereIs).exists, isFalse);
    });

    test('objects', () {
      final PartRef f = e('field "body" of card 3 of stack "hits"') as PartRef;
      expect(f.kind, 'field');
      final PartRef c = f.owner as PartRef;
      expect(c.owner, isA<StackRef>());
      expect(e('me'), isA<MeRef>());
      expect(e('Whetstone'), isA<AppRef>());
      expect((e('card id 7') as PartRef).id, isNotNull);
    });

    test('unary minus and not', () {
      expect((e('-x') as Unary).op, '-');
      expect((e('not x') as Unary).op, 'not');
    });
  });

  group('scripts', () {
    test('handlers and functions', () {
      final Script s = Parser.parseScript(
          'on mouseUp\n beep\nend mouseUp\n\nfunction f a, b\n return a\nend f\n');
      expect(s.handlers.length, 2);
      expect(s.find('MOUSEUP', function: false), isNotNull);
      expect(s.find('f', function: true)!.params, <String>['a', 'b']);
    });

    test('mismatched end is an error', () {
      expect(() => Parser.parseScript('on a\nend b\n'),
          throwsA(isA<ParseError>()));
    });

    test('missing end is an error', () {
      expect(() => Parser.parseScript('on a\n beep\n'),
          throwsA(isA<ParseError>()));
    });

    test('text outside a handler is an error', () {
      expect(() => Parser.parseScript('beep\n'), throwsA(isA<ParseError>()));
    });

    test('reserved words cannot be variables', () {
      expect(() => stmts('put 1 into card'), throwsA(isA<ParseError>()));
      expect(() => Parser.parseScript('on card\nend card\n'),
          throwsA(isA<ParseError>()));
    });

    test('error carries a line number', () {
      try {
        Parser.parseScript('on a\n beep\n put\nend a\n');
        fail('expected a ParseError');
      } on ParseError catch (e) {
        expect(e.line, isNotNull);
      }
    });
  });

  group('example files', () {
    void parses(String path, List<String> expectedHandlers) {
      final File f = File(path);
      if (!f.existsSync()) {
        markTestSkipped('$path not found');
        return;
      }
      final Script s = Parser.parseScript(f.readAsStringSync());
      expect(s.handlers.map((Handler h) => h.name).toList(), expectedHandlers);
    }

    test('grammar/examples/base.spk', () {
      parses('grammar/examples/base.spk', <String>[
        'mouseUp', 'newNote', 'finish', 'lookup', 'listCards', 'search',
        'nextHit', 'dropHit', 'howMany', 'clamp', 'mouseDown',
      ]);
    });

    test('Whetstone/examples/recipes.spk', () {
      parses('../Whetstone/examples/recipes.spk', <String>[
        'mouseUp', 'newRecipe', 'solved', 'findRecipe', 'listSymptoms',
        'isStale',
      ]);
    });
  });
}
