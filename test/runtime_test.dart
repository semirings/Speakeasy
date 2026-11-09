import 'package:speakeasy/speakeasy.dart';
import 'package:test/test.dart';

/// A field with a `text` property (the base host object has none).
class TextField extends BaseHostObject {
  TextField(String name, this.text) : super('field', name);
  String text;

  @override
  Object? getProperty(String property) =>
      property.toLowerCase() == 'text' ? text : super.getProperty(property);

  @override
  void setProperty(String property, Object? value) {
    if (property.toLowerCase() == 'text') {
      text = '$value';
    } else {
      super.setProperty(property, value);
    }
  }
}

/// A host object whose children are created with `text` fields.
class TestHost extends BaseHostObject {
  TestHost(super.kind, super.name);

  @override
  HostObject createChild(String kind, String name) {
    final BaseHostObject c = kind == 'field' ? TextField(name, '') : TestHost(kind, name);
    add(c);
    return c;
  }
}

class FakeIo extends Io {
  final List<String> replies = <String>[];
  final List<String> asked = <String>[];
  final List<String> answered = <String>[];
  final List<int> beeps = <int>[];
  final List<String> saved = <String>[];

  @override
  Future<String?> ask(String prompt, String defaultAnswer) async {
    asked.add(prompt);
    return replies.isEmpty ? null : replies.removeAt(0);
  }

  @override
  Future<String> answer(String message, List<String> buttons) async {
    answered.add(message);
    return buttons.isEmpty ? 'OK' : buttons.last;
  }

  @override
  void beep(int count) => beeps.add(count);

  @override
  Future<void> save(HostObject card) async => saved.add(card.name);
}

void main() {
  late BaseHostObject app;
  late BaseHostObject stack;
  late BaseHostObject camera;
  late BaseHostObject grease;
  late BaseHostObject render;
  late BaseHostObject button;
  late Runtime rt;

  BaseHostObject makeCard(String name, String symptom) {
    final BaseHostObject c = TestHost('card', name);
    c.add(TextField('symptom', symptom));
    c.add(TextField('status', 'stuck'));
    stack.add(c);
    return c;
  }

  setUp(() {
    app = BaseHostObject('app', 'Whetstone');
    stack = TestHost('stack', 'Recipes');
    app.add(stack);
    camera = makeCard('Camera fix', 'camera points nowhere');
    grease = makeCard('Grease pencil fill', 'no fill on grease pencil');
    render = makeCard('Render slow', 'render takes forever');
    button = BaseHostObject('button', 'Go');
    camera.add(button);
    rt = Runtime(app);
  });

  Future<String> msgAfter(String src) async {
    await rt.run(src);
    return rt.msg;
  }

  group('values and text', () {
    test('arithmetic and precedence', () async {
      expect(await msgAfter('put 2 + 3 * 4 into msg'), '14');
      expect(await msgAfter('put 10 / 4 into msg'), '2.5');
      expect(await msgAfter('put 7 div 2 into msg'), '3');
      expect(await msgAfter('put 7 mod 3 into msg'), '1');
      expect(await msgAfter('put 2 ^ 10 into msg'), '1024');
      expect(await msgAfter('put -3 + 1 into msg'), '-2');
    });

    test('variables and the add family', () async {
      expect(
          await msgAfter('put 5 into n\nadd 2 to n\nmultiply n by 3\n'
              'subtract 1 from n\ndivide n by 4\nput n into msg'),
          '5');
    });

    test('strings: concat, contains, case-insensitive compare', () async {
      expect(await msgAfter('put "a" & "b" && "c" into msg'), 'ab c');
      expect(await msgAfter('put "Hello" contains "ELL" into msg'), 'true');
      expect(await msgAfter('put "ABC" = "abc" into msg'), 'true');
      expect(await msgAfter('put "10" > "9" into msg'), 'true');
    });

    test('chunks read, put and delete', () async {
      expect(await msgAfter('put "a" & return & "b" into t\nput line 2 of t into msg'),
          'b');
      expect(await msgAfter('put "one two three" into t\nput word 2 of t into msg'),
          'two');
      expect(await msgAfter('put "abcdef" into t\nput char 2 to 4 of t into msg'),
          'bcd');
      expect(await msgAfter('put "a,b,c" into t\nput last item of t into msg'), 'c');
      expect(
          await msgAfter(
              'put "a,b,c" into t\nput "X" into item 2 of t\nput t into msg'),
          'a,X,c');
      expect(
          await msgAfter('put "a,b,c" into t\ndelete item 2 of t\nput t into msg'),
          'a,c');
      expect(await msgAfter('put "b" into t\nput "a" before t\nput "c" after t\nput t into msg'),
          'abc');
    });

    test('item delimiter', () async {
      expect(
          await msgAfter('set the itemDelimiter of Whetstone to ";"\n'
              'put item 2 of "a;b" into msg'),
          'b');
    });

    test('number of words, chars, lines', () async {
      expect(await msgAfter('put the number of words in "a b c" into msg'), '3');
      expect(await msgAfter('put the number of chars in "abcd" into msg'), '4');
      expect(
          await msgAfter(
              'put "a" & return & "b" into t\nput the number of lines in t into msg'),
          '2');
    });

    test('type tests and versions', () async {
      expect(await msgAfter('put "12" is a number into msg'), 'true');
      expect(await msgAfter('put "x" is a number into msg'), 'false');
      expect(await msgAfter('put "5.10" is newer than "5.2" into msg'), 'true');
      expect(await msgAfter('put "5.2" is older than "5.10" into msg'), 'true');
      expect(await msgAfter('put "5.2" is not older than "5.2" into msg'), 'true');
    });

    test('built-in functions', () async {
      expect(await msgAfter('put max(3, 9, 4) into msg'), '9');
      expect(await msgAfter('put round(2.5) into msg'), '3');
      expect(await msgAfter('put the length of "abc" into msg'), '3');
      expect(await msgAfter('put offset("b", "abc") into msg'), '2');
      expect(await msgAfter('put the sum of "1,2,3" into msg'), '6');
      expect(await msgAfter('put value("2+3") into msg'), '5');
    });

    test('date uses the clock', () async {
      final Runtime r = Runtime(app, clock: () => DateTime(2026, 11, 9, 14, 5, 9));
      await r.run('put the date into msg');
      expect(r.msg, '2026-11-09');
      await r.run('put the long date into msg');
      expect(r.msg, 'Monday, November 9, 2026');
      await r.run('put the long time into msg');
      expect(r.msg, '14:05:09');
    });
  });

  group('control flow', () {
    test('if / else', () async {
      expect(await msgAfter('if 1 < 2 then put "y" into msg\nelse put "n" into msg'), 'y');
      expect(
          await msgAfter('if 1 > 2 then\nput "y" into msg\nelse\nput "n" into msg\nend if'),
          'n');
    });

    test('repeat forms', () async {
      expect(
          await msgAfter('put 0 into total\nrepeat with i = 1 to 5\nadd i to total\n'
              'end repeat\nput total into msg'),
          '15');
      expect(await msgAfter('put 0 into n\nrepeat 3 times\nadd 1 to n\nend repeat\nput n into msg'),
          '3');
      expect(
          await msgAfter('put 0 into n\nrepeat until n = 4\nadd 1 to n\nend repeat\nput n into msg'),
          '4');
      expect(
          await msgAfter(
              'put "" into s\nrepeat with i = 3 down to 1\nput i after s\nend repeat\nput s into msg'),
          '321');
    });

    test('exit repeat and next repeat', () async {
      expect(
          await msgAfter('put 0 into n\nrepeat 10 times\nadd 1 to n\n'
              'if n = 3 then exit repeat\nend repeat\nput n into msg'),
          '3');
      expect(
          await msgAfter('put "" into s\nrepeat with i = 1 to 5\n'
              'if i mod 2 = 0 then next repeat\nput i after s\nend repeat\nput s into msg'),
          '135');
    });

    test('do runs a string', () async {
      expect(await msgAfter('do "put 5 into msg"'), '5');
    });

    test('a runaway script is stopped', () async {
      final Runtime r = Runtime(app, maxSteps: 1000);
      await expectLater(() => r.run('repeat forever\nend repeat'), throwsA(isA<ScriptError>()));
    });
  });

  group('handlers and messages', () {
    test('functions with parameters and recursion', () async {
      camera.script = 'function fact n\n'
          '  if n <= 1 then return 1\n'
          '  return n * fact(n - 1)\n'
          'end fact\n';
      expect(await msgAfter('put fact(5) into msg'), '120');
    });

    test('runaway recursion is stopped', () async {
      camera.script = 'function f\n return f()\nend f\n';
      await expectLater(() => rt.run('put f() into msg'), throwsA(isA<ScriptError>()));
    });

    test('message path and pass', () async {
      camera.script = 'on hello\n put "card" into msg\n pass hello\nend hello\n';
      stack.script = 'on hello\n put msg & "+stack" into msg\nend hello\n';
      await rt.send('hello', camera);
      expect(rt.msg, 'card+stack');
    });

    test('without pass the message stops', () async {
      camera.script = 'on hello\n put "card" into msg\nend hello\n';
      stack.script = 'on hello\n put "stack" into msg\nend hello\n';
      await rt.send('hello', camera);
      expect(rt.msg, 'card');
    });

    test('a button handler runs', () async {
      button.script = 'on mouseUp\n put "clicked" into msg\nend mouseUp\n';
      await rt.send('mouseUp', button);
      expect(rt.msg, 'clicked');
    });

    test('statement-level handler call with arguments', () async {
      camera.script = 'on show2 a, b\n put a & b into msg\nend show2\n';
      expect(await msgAfter('show2 "x", "y"'), 'xy');
    });

    test('unknown handler is an error', () async {
      await expectLater(() => rt.run('nosuch'), throwsA(isA<ScriptError>()));
    });

    test('globals are shared between handlers', () async {
      camera.script = 'on setIt\n global g\n put 5 into g\nend setIt\n'
          'on getIt\n global g\n put g into msg\nend getIt\n';
      await rt.send('setIt', camera);
      await rt.send('getIt', camera);
      expect(rt.msg, '5');
    });

    test('exit handler and return', () async {
      camera.script = 'on t\n put "a" into msg\n exit t\n put "b" into msg\nend t\n';
      await rt.send('t', camera);
      expect(rt.msg, 'a');
    });

    test('a broken script reports its owner', () async {
      camera.script = 'on t\n put\nend t\n';
      await expectLater(() => rt.send('t', camera), throwsA(isA<ScriptError>()));
    });
  });

  group('cards and navigation', () {
    test('start on the first card; counts', () async {
      expect(rt.currentCard, same(camera));
      expect(await msgAfter('put the number of cards into msg'), '3');
    });

    test('go to by name, number, position', () async {
      await rt.run('go to card "Render slow"');
      expect(rt.currentCard, same(render));
      await rt.run('go to first card');
      expect(rt.currentCard, same(camera));
      await rt.run('go to next card');
      expect(rt.currentCard, same(grease));
      await rt.run('go to previous card');
      expect(rt.currentCard, same(camera));
      await rt.run('go to last card');
      expect(rt.currentCard, same(render));
      await rt.run('go to next card');
      expect(rt.currentCard, same(camera), reason: 'next wraps around');
      await rt.run('go to card 2');
      expect(rt.currentCard, same(grease));
    });

    test('fields of cards', () async {
      expect(await msgAfter('put field "symptom" of card 2 into msg'),
          'no fill on grease pencil');
      await rt.run('put "hello" into field "symptom"');
      expect((camera.find('field', 'symptom')! as TextField).text, 'hello');
    });

    test('properties and there is', () async {
      expect(await msgAfter('put the name of card 2 into msg'), 'Grease pencil fill');
      expect(await msgAfter('put the number of this card into msg'), '1');
      expect(await msgAfter('put there is a card "Render slow" into msg'), 'true');
      expect(await msgAfter('put there is no card "zzz" into msg'), 'true');
      await rt.run('set the name of this card to "Z"');
      expect(camera.name, 'Z');
    });

    test('create card makes it current; create field; delete', () async {
      await rt.run('create card "New"\ncreate field "symptom"\n'
          'put "hi" into field "symptom"');
      expect(stack.children.length, 4);
      expect(rt.currentCard!.name, 'New');
      expect(await msgAfter('put field "symptom" into msg'), 'hi');
      await rt.run('delete this card');
      expect(stack.children.length, 3);
      expect(rt.currentCard, isNotNull);
    });

    test('find text in a field goes to the card', () async {
      await rt.run('find "grease" in field "symptom"');
      expect(rt.currentCard, same(grease));
      await rt.run('find "nothing like this" in field "symptom"');
      expect(rt.result, 'not found');
      expect(rt.currentCard, same(grease));
    });
  });

  group('substacks', () {
    test('find cards where ... into stack', () async {
      await rt.run('find cards where field "symptom" contains "camera" into stack "hits"');
      final SubStack hits = rt.substacks['hits']!;
      expect(hits.cards, <HostObject>[camera]);
      expect(rt.substack, isNull, reason: 'find does not move you');
      expect(await msgAfter('put the number of cards of stack "hits" into msg'), '1');
    });

    test('default name is found', () async {
      await rt.run('find cards where field "symptom" contains "render"');
      expect(rt.substacks['found']!.cards, <HostObject>[render]);
    });

    test('go to stack walks the cursor', () async {
      await rt.run('find cards where true into stack "all"\ngo to stack "all"');
      expect(rt.substack!.name, 'all');
      expect(rt.currentCard, same(camera));
      await rt.run('go to next card');
      expect(rt.currentCard, same(grease));
      await rt.run('go to last card');
      expect(rt.currentCard, same(render));
      expect(await msgAfter('put the name of card 2 of stack "all" into msg'),
          'Grease pencil fill');
      await rt.run('go to stack "Recipes"');
      expect(rt.substack, isNull);
      expect(rt.currentCard, same(camera));
    });

    test('drop removes from the substack only', () async {
      await rt.run('find cards where true into stack "all"\ngo to stack "all"\n'
          'go to next card\ndrop this card');
      expect(rt.substacks['all']!.cards, <HostObject>[camera, render]);
      expect(stack.children.length, 3, reason: 'the real card is untouched');
      expect(rt.currentCard, same(render), reason: 'cursor moves on');
    });

    test('drop without a substack is an error', () async {
      await expectLater(() => rt.run('drop this card'), throwsA(isA<ScriptError>()));
    });

    test('delete removes the real card and the references', () async {
      await rt.run('find cards where true into stack "all"\ngo to stack "all"\n'
          'delete this card');
      expect(stack.children.length, 2);
      expect(rt.substacks['all']!.cards.length, 2);
      expect(rt.currentCard, same(grease));
    });

    test('a numeric where scores and orders the results', () async {
      await rt.run('find cards where length of field "symptom" into stack "hits"\n'
          'go to stack "hits"');
      expect(rt.substacks['hits']!.cards, <HostObject>[grease, camera, render]);
      expect(await msgAfter('put the score of this card into msg'), '24');
    });

    test('sort a substack', () async {
      await rt.run('find cards where true into stack "all"\ngo to stack "all"\n'
          'sort cards descending numeric by length of field "symptom"');
      expect(rt.substacks['all']!.cards, <HostObject>[grease, camera, render]);
    });

    test('reusing a name replaces the substack', () async {
      await rt.run('find cards where true into stack "x"');
      await rt.run('find cards where false into stack "x"');
      expect(rt.substacks['x']!.cards, isEmpty);
    });

    test('substacks survive until replaced and are snapshots', () async {
      await rt.run('find cards where field "symptom" contains "camera" into stack "hits"');
      await rt.run('put "no longer" into field "symptom"');
      expect(rt.substacks['hits']!.cards, <HostObject>[camera]);
    });
  });

  group('user interface hooks', () {
    test('ask and answer set it', () async {
      final FakeIo io = FakeIo()..replies.add('Bob');
      rt.io = io;
      await rt.run('ask "Name?"\nput it into msg');
      expect(rt.msg, 'Bob');
      expect(io.asked, <String>['Name?']);
      await rt.run('answer "Sure?" with "Yes" or "No"\nput it into msg');
      expect(rt.msg, 'No');
    });

    test('a cancelled ask sets the result', () async {
      rt.io = FakeIo();
      await rt.run('ask "Name?"');
      expect(rt.result, 'Cancel');
    });

    test('beep and save', () async {
      final FakeIo io = FakeIo();
      rt.io = io;
      await rt.run('beep 2\nsave');
      expect(io.beeps, <int>[2]);
      expect(io.saved, <String>['Camera fix']);
    });

    test('onChange fires once per run', () async {
      int n = 0;
      rt.onChange = () => n++;
      await rt.run('put 1 into msg\nput 2 into msg');
      expect(n, 1);
    });
  });

  group('errors', () {
    test('unknown variable names the line', () async {
      try {
        await rt.run('put 1 into x\nput y into msg');
        fail('expected a ScriptError');
      } on ScriptError catch (e) {
        expect(e.line, 2);
        expect(e.message, contains("'y'"));
      }
    });

    test('divide by zero', () async {
      await expectLater(() => rt.run('put 1 / 0 into msg'), throwsA(isA<ScriptError>()));
    });

    test('text where a number is needed', () async {
      await expectLater(() => rt.run('put "abc" + 1 into msg'), throwsA(isA<ScriptError>()));
    });

    test('missing card', () async {
      await expectLater(() => rt.run('go to card "nope"'), throwsA(isA<ScriptError>()));
    });

    test('unknown property', () async {
      await expectLater(() => rt.run('put the zorp of this card into msg'),
          throwsA(isA<SpeakeasyError>()));
    });

    test('syntax errors surface as ParseError', () async {
      await expectLater(() => rt.run('put into'), throwsA(isA<ParseError>()));
    });
  });
}
