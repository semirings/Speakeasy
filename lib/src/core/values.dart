/// Values and conversions. Speakeasy values are String, double or bool;
/// an object reference is a HostObject. Text is the common currency, as in
/// HyperTalk: "3" and 3 are the same number, comparisons ignore case.
library;

import 'errors.dart';
import 'host.dart';

/// Number as text: integers without ".0".
String formatNumber(double d) {
  if (d.isNaN || d.isInfinite) throw ScriptError('the result is not a number');
  if (d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

String toStr(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is double) return formatNumber(v);
  if (v is int) return v.toString();
  if (v is bool) return v ? 'true' : 'false';
  if (v is HostObject) return v.name;
  return '$v';
}

double? tryNum(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) {
    final String s = v.trim();
    if (s.isEmpty) return null;
    final double? d = double.tryParse(s.endsWith('.') ? '${s}0' : s);
    if (d == null || d.isNaN || d.isInfinite) return null;
    return d;
  }
  return null;
}

bool isNumeric(Object? v) => tryNum(v) != null;

/// Empty text counts as 0 in arithmetic; other non-numbers are an error.
double toNum(Object? v) {
  if (v is String && v.trim().isEmpty) return 0;
  final double? d = tryNum(v);
  if (d == null) throw ScriptError('can\'t use "${toStr(v)}" as a number');
  return d;
}

bool toBool(Object? v) {
  if (v is bool) return v;
  if (v is String) {
    final String s = v.trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  throw ScriptError('expected true or false but found "${toStr(v)}"');
}

/// -1, 0 or 1. Numbers compare as numbers, anything else as lower-case text.
int compareValues(Object? a, Object? b) {
  final double? x = tryNum(a);
  final double? y = tryNum(b);
  if (x != null && y != null) return x.compareTo(y);
  return toStr(a).toLowerCase().compareTo(toStr(b).toLowerCase());
}

bool valuesEqual(Object? a, Object? b) => compareValues(a, b) == 0;

/// Compares dotted version strings: "5.10" is newer than "5.2".
int compareVersions(Object? a, Object? b) {
  List<int> parse(Object? v) {
    final String s = toStr(v).trim();
    if (s.isEmpty) throw ScriptError('"" is not a version');
    final List<int> out = <int>[];
    for (final String part in s.split('.')) {
      final int? n = int.tryParse(part);
      if (n == null || n < 0) throw ScriptError('"$s" is not a version');
      out.add(n);
    }
    return out;
  }

  final List<int> x = parse(a);
  final List<int> y = parse(b);
  final int n = x.length > y.length ? x.length : y.length;
  for (int i = 0; i < n; i++) {
    final int p = i < x.length ? x[i] : 0;
    final int q = i < y.length ? y[i] : 0;
    if (p != q) return p < q ? -1 : 1;
  }
  return 0;
}
