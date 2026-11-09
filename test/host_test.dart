import 'package:speakeasy/speakeasy.dart';
import 'package:test/test.dart';

void main() {
  late BaseHostObject app;
  late BaseHostObject stack;
  late BaseHostObject card;
  late BaseHostObject button;

  setUp(() {
    app = BaseHostObject('app', 'Whetstone');
    stack = BaseHostObject('stack', 'Recipes');
    card = BaseHostObject('card', 'Camera fix');
    button = BaseHostObject('button', 'Replay', script: 'on mouseUp\nend mouseUp');
    app.add(stack);
    stack.add(card);
    card.add(button);
  });

  test('message path runs button, card, stack, app', () {
    final List<String> path = <String>[];
    HostObject? o = button;
    while (o != null) {
      path.add(o.kind);
      o = o.parent;
    }
    expect(path, <String>['button', 'card', 'stack', 'app']);
  });

  test('find matches name case-insensitively and by id', () {
    expect(stack.find('card', 'camera FIX'), same(card));
    expect(stack.find('card', card.id), same(card));
    expect(stack.find('button', 'Replay'), isNull); // wrong kind at this level
    expect(card.find('button', 'replay'), same(button));
  });

  test('properties are case-insensitive', () {
    expect(card.getProperty('NAME'), 'Camera fix');
    card.setProperty('Name', 'Camera reset');
    expect(card.name, 'Camera reset');
    expect(button.getProperty('script'), contains('mouseUp'));
  });

  test('unknown property throws', () {
    expect(() => card.getProperty('colour'), throwsArgumentError);
    expect(() => card.setProperty('id', 'x'), throwsArgumentError);
  });

  test('ids are unique', () {
    expect(<String>{app.id, stack.id, card.id, button.id}.length, 4);
  });
}
