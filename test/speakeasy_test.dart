import 'package:speakeasy/speakeasy.dart';
import 'package:test/test.dart';

void main() {
  test('version is set', () {
    expect(speakeasyVersion, isNotEmpty);
  });
}
