# base.ebnf, d4m.ebnf, blender.ebnf: notes (DRAFT 1)

Check: `python3 -I check_ebnf.py base.ebnf d4m.ebnf blender.ebnf`
Last result: 104 rules, 7 extensions, 0 duplicate, 0 undefined. This proves consistency, **not** that any script parses.
Examples are in `examples/*.spk`; they become the parser's tests.

## How extensions work
Base defines six extension points: `command`, `object`, `function`, `constant`, `THEFUNC`, `PROPERTY`.
An extension file adds alternatives with `rule += ...` and may define new rules. It cannot change anything else.
d4m and blender never refer to each other. The parser keeps a table of registered commands, so an extension is loaded by registering its entries, not by changing the parser.

## What changed from hypertalk-2.2.ebnf
- **Strings are quoted only.** `UNQUOTED` is gone.
- **Keywords are reserved.** A variable cannot be named `card`, `put`, `object`, ...
- **Objects:** `Whetstone`, `stack`, `card`, `field`, `button`, `me`, `target`. No backgrounds, menus, windows, pictures. `field "x" of card 3` replaces the `bkgnd` forms.
- **Commands kept (20):** add, answer, ask, beep, create, delete, divide, drop, find, get, go, hide, multiply, put, save, set, show, sort, subtract, wait.
- **Changed:** `save` saves the current card; `create` makes a card, button or field.
- **Dropped (everything else):** select, arrowKey, choose, click, close, commandKey, controlKey, convert, debug, dial, disable, doMenu, drag, edit, enable, export, flash, functionKey, help, import, lock, mark, open, play, pop, print, push, read, reset, start, stop, type, unlock, unmark, visual, write.
- **Functions:** 23 kept (math, text, date, `number of`). Mouse, click, key, finance, trig, system, selected-chunk functions dropped.
- **Properties:** id, name, script, text, visible, number, itemDelimiter.
- **Dropped keyword forms:** `exit to HyperCard`, `send ... to program|window`.

## Decisions in DRAFT 2 (substacks and versions)
- **`find cards where EXPR [into stack NAME]`** makes a substack: an ordered set of *references* to cards of the current stack, with a cursor. It is addressed as a stack by name; without `into` it is called "found". `EXPR` is evaluated once per candidate card with that card as `this card`.
- The substack is a snapshot, temporary (replaced when the name is reused), and navigated with the ordinary `go to next|previous|first|last card`, `the number of cards of stack`, `card 3 of stack "hits"`.
- **`delete`** removes the card itself; **`drop card`** removes it from the substack only.
- `go to next card`, `first card of stack "hits"` etc. now parse (the old rule had `card next`, which was wrong).
- **Versions.** `is [not] newer than` / `older than` compare dotted numbers: "5.10" is newer than "5.2".
- New property: `score` (relevance of a card in a substack).
- Not in the grammar (interpreter behaviour): substacks never change card parents; a `where` that names a missing field is an error.

## Known gaps (need a decision or a parser to settle)
1. **Vectors are not expressions.** `0,0,1.5` is a `point` only where blender.ebnf says so; `set the location of object "Eye" to 0,0,1` is not accepted by base's `set`. Options: a vector literal in base, or a Blender-only `set` form.
2. **Words that are both command and property.** `scale` is a Blender command and a property. Allowed because the position decides, but the lexer must keep keywords as keywords and let the parser choose.
3. **`it`.** Not defined here. HyperTalk sets `it` after `ask`/`get`; Speakeasy must define it (as an ordinary variable set by those commands).
4. **`if ... then` with newlines** is the classic HyperTalk difficulty. The rule copies 2.2 and is untested.
5. **Precedence** is the documented HyperTalk order, unverified.
6. **Message path.** `pass`, `send`, and handler lookup follow button, card, stack, Whetstone; that lives in the interpreter, not the grammar.
7. **Fields are addressed by name:** `field "body"`. No grammar for typed access (`the symptom of this card`). Possible later.
8. **Messages.** `mouseUp` and friends are just identifiers; which ones Whetstone sends is a design question.
9. **d4m and blender are starters:** a handful of commands each, for review. Weight-space and ontology commands are not here.
