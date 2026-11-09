/// What a Speakeasy script can name and act on.
///
/// Speakeasy never imports Flutter. The application (Whetstone) provides
/// objects that implement [HostObject]; the interpreter sees only this
/// interface. [BaseHostObject] is a ready-made implementation to extend.
library;

abstract class HostObject {
  /// Unique id within the application.
  String get id;

  /// One of 'app', 'stack', 'card', 'field', 'button'.
  String get kind;

  String get name;
  set name(String value);

  /// Speakeasy source attached to this object ('' if none).
  String get script;
  set script(String value);

  /// Next object up the message path (button, card, stack, app), or null.
  HostObject? get parent;

  List<HostObject> get children;

  /// Property names are case-insensitive. Throws [ArgumentError] if unknown.
  Object? getProperty(String property);
  void setProperty(String property, Object? value);

  /// First child of [ofKind] whose id, or name (case-insensitive), equals [key].
  HostObject? find(String ofKind, String key);

  /// Makes a new child of [kind] named [name] and adds it. Used by the
  /// `create` command. Override to build your own card/field/button classes.
  HostObject createChild(String kind, String name);

  /// Removes [child]. Used by `delete`. Returns false if it was not a child.
  bool removeChild(HostObject child);
}

/// A plain [HostObject] with id, kind, name, script, parent and children.
/// Subclasses add their own properties by overriding [getProperty] and
/// [setProperty] and falling back to `super`.
class BaseHostObject implements HostObject {
  BaseHostObject(this.kind, this.name, {String? id, this.script = ''})
      : id = id ?? '${++_counter}';

  static int _counter = 0;

  @override
  final String id;

  @override
  final String kind;

  @override
  String name;

  @override
  String script;

  @override
  HostObject? parent;

  final List<BaseHostObject> _children = <BaseHostObject>[];

  @override
  List<HostObject> get children => List<HostObject>.unmodifiable(_children);

  /// Adds [child] and makes this object its parent.
  void add(BaseHostObject child) {
    child.parent = this;
    _children.add(child);
  }

  @override
  Object? getProperty(String property) {
    switch (property.toLowerCase()) {
      case 'id':
        return id;
      case 'kind':
        return kind;
      case 'name':
        return name;
      case 'script':
        return script;
    }
    throw ArgumentError.value(property, 'property', 'no such property on a $kind');
  }

  @override
  void setProperty(String property, Object? value) {
    switch (property.toLowerCase()) {
      case 'name':
        name = '$value';
        return;
      case 'script':
        script = '$value';
        return;
    }
    throw ArgumentError.value(property, 'property', 'cannot be set on a $kind');
  }

  @override
  HostObject createChild(String kind, String name) {
    final BaseHostObject child = BaseHostObject(kind, name);
    add(child);
    return child;
  }

  @override
  bool removeChild(HostObject child) {
    final bool removed = _children.remove(child);
    if (removed && child is BaseHostObject) child.parent = null;
    return removed;
  }

  @override
  HostObject? find(String ofKind, String key) {
    final String lower = key.toLowerCase();
    for (final BaseHostObject c in _children) {
      if (c.kind == ofKind && (c.id == key || c.name.toLowerCase() == lower)) {
        return c;
      }
    }
    return null;
  }
}
