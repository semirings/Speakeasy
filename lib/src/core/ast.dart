/// Syntax tree for Speakeasy base. One node class per grammar construct that
/// the interpreter must tell apart. Nodes are plain data.
library;

// ---------------------------------------------------------------- script

final class Script {
  const Script(this.handlers);
  final List<Handler> handlers;

  /// First handler called [name] (case-insensitive), or null.
  Handler? find(String name, {required bool function}) {
    final String lower = name.toLowerCase();
    for (final Handler h in handlers) {
      if (h.isFunction == function && h.name.toLowerCase() == lower) return h;
    }
    return null;
  }
}

final class Handler {
  const Handler(this.name, this.isFunction, this.params, this.body, this.line);
  final String name;
  final bool isFunction;
  final List<String> params;
  final List<Stmt> body;
  final int line;
}

// ----------------------------------------------------------- expressions

sealed class Expr {
  const Expr();
}

/// A string, a number (double) or a boolean.
final class Literal extends Expr {
  const Literal(this.value);
  final Object value;
}

final class Variable extends Expr {
  const Variable(this.name);
  final String name;
}

/// op is one of: or and = <> < > <= >= contains in & && + - * / div mod ^
final class Binary extends Expr {
  const Binary(this.op, this.left, this.right);
  final String op;
  final Expr left;
  final Expr right;
}

/// op is '-' or 'not'.
final class Unary extends Expr {
  const Unary(this.op, this.operand);
  final String op;
  final Expr operand;
}

/// `x is a number`, `x is not an integer`.
final class TypeTest extends Expr {
  const TypeTest(this.operand, this.typeName, this.negated);
  final Expr operand;
  final String typeName;
  final bool negated;
}

/// `a is newer than b`, `a is not older than b`.
final class VersionCompare extends Expr {
  const VersionCompare(this.left, this.right,
      {required this.newer, required this.negated});
  final Expr left;
  final Expr right;
  final bool newer;
  final bool negated;
}

/// `there is a card "x"` (exists true) or `there is no card "x"`.
final class ThereIs extends Expr {
  const ThereIs(this.target, {required this.exists});
  final ObjectRef target;
  final bool exists;
}

/// One step of a chunk expression. [unit] is char, word, item or line.
/// Either [from] (and optionally [to]) is set, or [which] is
/// 'last', 'middle' or 'any'. 'first'..'tenth' become [from] = 1..10.
final class ChunkItem {
  const ChunkItem(this.unit, {this.from, this.to, this.which});
  final String unit;
  final Expr? from;
  final Expr? to;
  final String? which;
}

/// `word 2 of line 1 of x`: [chunks] are in the order written (outermost first).
final class ChunkExpr extends Expr {
  const ChunkExpr(this.chunks, this.source);
  final List<ChunkItem> chunks;
  final Expr source;
}

/// A built-in or user function call. [name] is as written.
/// [adjective] is 'long', 'short' or 'abbrev' for `the long date`.
final class FuncCall extends Expr {
  const FuncCall(this.name, this.args, {this.adjective});
  final String name;
  final List<Expr> args;
  final String? adjective;
}

/// `the number of cards of stack "x"`. [what] is cards, fields, buttons,
/// chars, words, items or lines. [scope] is a stack (for cards) or a card
/// (for fields, buttons); [source] is the text for chars/words/items/lines.
final class NumberOf extends Expr {
  const NumberOf(this.what, {this.scope, this.source});
  final String what;
  final ObjectRef? scope;
  final Expr? source;
}

/// `the name of this card`. [target] is an [ObjectRef] or a [ChunkExpr]
/// whose source is a field.
final class PropertyRef extends Expr {
  const PropertyRef(this.property, this.target);

  /// Lower-case property name.
  final String property;
  final Expr target;
}

/// Containers that are not objects.
final class MsgRef extends Expr {
  const MsgRef();
}

final class SelectionRef extends Expr {
  const SelectionRef();
}

// --------------------------------------------------------------- objects

sealed class ObjectRef extends Expr {
  const ObjectRef();
}

final class MeRef extends ObjectRef {
  const MeRef();
}

final class TargetRef extends ObjectRef {
  const TargetRef();
}

/// The word `Whetstone`: the application.
final class AppRef extends ObjectRef {
  const AppRef();
}

/// A card, field or button. [kind] is 'card', 'field' or 'button'.
/// Exactly one of [value], [id], [position] is set:
///   value    card "Notes" / card 3 / first card (a Literal 1)
///   id       card id 7
///   position next prev this last any
/// [owner] is a [StackRef] for cards (`of stack "hits"`), a card [PartRef]
/// for fields and buttons; null means the current one.
final class PartRef extends ObjectRef {
  const PartRef(this.kind, {this.value, this.id, this.position, this.owner});
  final String kind;
  final Expr? value;
  final Expr? id;
  final String? position;
  final ObjectRef? owner;
}

/// `stack`, `this stack` (name null: the current stack) or `stack "hits"`.
final class StackRef extends ObjectRef {
  const StackRef({this.name});
  final Expr? name;
}

// ------------------------------------------------------------- statements

/// A container written as chunks of a base: `line 2 of field "x"`.
/// [base] is a [Variable], a field [PartRef], a [MsgRef] or a [SelectionRef].
final class TextTarget {
  const TextTarget(this.chunks, this.base);
  final List<ChunkItem> chunks;
  final Expr base;
}

sealed class Stmt {
  const Stmt(this.line);
  final int line;
}

/// mode is 'into', 'before', 'after' or null (put into the message box).
final class Put extends Stmt {
  const Put(super.line, this.value, this.mode, this.target);
  final Expr value;
  final String? mode;
  final TextTarget? target;
}

final class Get extends Stmt {
  const Get(super.line, this.value);
  final Expr value;
}

/// [target] is an [ObjectRef] or a [ChunkExpr] whose source is a field.
final class SetProp extends Stmt {
  const SetProp(super.line, this.property, this.target, this.value);
  final String property;
  final Expr target;
  final Expr value;
}

/// op is add, subtract, multiply or divide.
final class Arith extends Stmt {
  const Arith(super.line, this.op, this.value, this.target);
  final String op;
  final Expr value;
  final TextTarget target;
}

/// [target] is a card [PartRef] or a [StackRef].
final class Go extends Stmt {
  const Go(super.line, this.target);
  final ObjectRef target;
}

/// `find cards where EXPR [into stack NAME]`.
final class FindCards extends Stmt {
  const FindCards(super.line, this.where, this.into);
  final Expr where;
  final StackRef? into;
}

/// `find EXPR [in field]`.
final class FindText extends Stmt {
  const FindText(super.line, this.text, this.field);
  final Expr text;
  final PartRef? field;
}

final class Drop extends Stmt {
  const Drop(super.line, this.card);
  final PartRef card;
}

final class Sort extends Stmt {
  const Sort(super.line, this.key,
      {required this.descending, required this.mode});
  final Expr key;
  final bool descending;

  /// 'text', 'numeric' or null (decide per value).
  final String? mode;
}

/// [kind] is card, button or field.
final class Create extends Stmt {
  const Create(super.line, this.kind, this.name);
  final String kind;
  final Expr? name;
}

final class DeleteObject extends Stmt {
  const DeleteObject(super.line, this.target);
  final ObjectRef target;
}

final class DeleteText extends Stmt {
  const DeleteText(super.line, this.target);
  final TextTarget target;
}

final class Save extends Stmt {
  const Save(super.line);
}

/// `show`/`hide` an object.
final class ShowHide extends Stmt {
  const ShowHide(super.line, this.target, {required this.show});
  final ObjectRef target;
  final bool show;
}

/// `show msg box` / `hide msg box`.
final class ShowHideMsgBox extends Stmt {
  const ShowHideMsgBox(super.line, {required this.show});
  final bool show;
}

final class Answer extends Stmt {
  const Answer(super.line, this.message, this.buttons);
  final Expr message;
  final List<Expr> buttons;
}

final class Ask extends Stmt {
  const Ask(super.line, this.prompt, this.defaultAnswer);
  final Expr prompt;
  final Expr? defaultAnswer;
}

final class Beep extends Stmt {
  const Beep(super.line, this.count);
  final Expr? count;
}

/// kind is 'until', 'while' or 'time'. For 'time', [unit] is 'ticks' or 'seconds'.
final class Wait extends Stmt {
  const Wait(super.line, this.kind, {this.cond, this.amount, this.unit});
  final String kind;
  final Expr? cond;
  final Expr? amount;
  final String? unit;
}

final class Do extends Stmt {
  const Do(super.line, this.source);
  final Expr source;
}

final class ExitRepeat extends Stmt {
  const ExitRepeat(super.line);
}

final class ExitHandler extends Stmt {
  const ExitHandler(super.line, this.name);
  final String name;
}

final class NextRepeat extends Stmt {
  const NextRepeat(super.line);
}

final class Global extends Stmt {
  const Global(super.line, this.names);
  final List<String> names;
}

final class Pass extends Stmt {
  const Pass(super.line, this.message);
  final String message;
}

final class Return extends Stmt {
  const Return(super.line, this.value);
  final Expr? value;
}

final class Send extends Stmt {
  const Send(super.line, this.message, this.target);
  final Expr message;
  final ObjectRef target;
}

/// A call of a handler by name: `lookup`, `clamp 1, 2, 3`.
final class MessageSend extends Stmt {
  const MessageSend(super.line, this.name, this.args);
  final String name;
  final List<Expr> args;
}

final class If extends Stmt {
  const If(super.line, this.cond, this.thenBody, this.elseBody);
  final Expr cond;
  final List<Stmt> thenBody;
  final List<Stmt> elseBody;
}

/// kind is forever, until, while, times or with.
final class Repeat extends Stmt {
  const Repeat(super.line, this.kind, this.body,
      {this.cond,
      this.count,
      this.variable,
      this.from,
      this.to,
      this.down = false});
  final String kind;
  final List<Stmt> body;
  final Expr? cond;
  final Expr? count;
  final String? variable;
  final Expr? from;
  final Expr? to;
  final bool down;
}
