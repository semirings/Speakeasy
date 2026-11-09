import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('core does not import extensions', () {
    final bad = <String>[];
    for (final f in Directory('lib/src/core').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final bool imports = f
          .readAsLinesSync()
          .where((String l) => l.startsWith('import ') || l.startsWith('export '))
          .any((String l) => l.contains('extensions/'));
      if (imports) bad.add(f.path);
    }
    expect(bad, isEmpty);
  });

  test('d4m and blender do not import each other', () {
    final d4m = File('lib/src/extensions/d4m.dart').readAsStringSync();
    final blender = File('lib/src/extensions/blender.dart').readAsStringSync();
    expect(d4m.contains('blender.dart'), isFalse);
    expect(blender.contains('d4m.dart'), isFalse);
  });
}
