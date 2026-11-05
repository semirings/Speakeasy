# grammar/ notes

`hypertalk-2.2.ebnf` restates DeVoto's HyperTalk 2.2 BNF (jaedworks.com/hypercard/scripts/hypertalk-bnf.html)
in a regular EBNF. It is a **reference**, not the Speakeasy grammar. Speakeasy will be a subset (plus
additions for D4M) written as its own file, derived from this one.

Mechanical check: `python3 check_ebnf.py hypertalk-2.2.ebnf` finds duplicate and undefined rules and
unbalanced parentheses. Last run: 156 rules, 0 duplicate, 0 undefined. It does **not** check that the
grammar parses real HyperTalk or that it is unambiguous.

## Changes from the source

### FIXED (defects in the source)
- `autoSelectautoTab` was one token; split into `autoSelect | autoTab`.
- `eigth` -> `eighth`.
- `return` added to the constants.
- `window`, `duration`, and the style / textAlign / textStyle value lists were each defined twice; merged.
- `<chunk> <expr>` changed to `chunk factor`: a chunk binds to the next factor, not a whole expression.
- Stray `Ê` characters, a stray `integer>`, `not <expr`, and an unbalanced brace in `<card>` removed.

### ADDED (missing from the source)
- `function` handlers and handler parameters (source has parameterless `on` handlers only).
- `messageSend` (used, never defined), `identList`, and the other undefined terms.
- `COMMENT` (`--`) and `CONTINUATION` (`¬`) lexical rules.
- Operator precedence layering. The source lists operators flat.
  **Unverified** against real HyperCard behaviour.
- An optional `of` before `selectedButton ... family` is a guess.

### NORMALIZED (source ambiguous or garbled; one reading chosen)
- `send ... to` alternatives.
- `propertyRef` now allows an optional `the`.
- `partRef` (`id n | ordinal | n`) is shared by buttons and fields.
- Typed nonterminals (`integer`, `logical`, ...) collapse to `expr`: type errors are run-time errors.
- `propVal` is one flat list; which values are legal for which property is a semantic check.

## Known gaps
- Command bodies were reconstructed from the 2.2 source and general HyperTalk knowledge. The file has
  **54** commands, not the 62 I estimated earlier. Diff against the source's command list before
  trusting completeness.
- Some command syntax is loose (`print`, `show`, `select`, `answer`).
- Newline handling inside `if/then/else` is the classic HyperTalk trouble spot and is only approximated.
- Keywords are case-insensitive, so the lexer should lower-case before matching.

## Speakeasy decisions still open
- Quoted string literals only (recommended) versus HyperTalk's unquoted tokens (`UNQUOTED`).
- Which commands to keep; Speakeasy needs a small fixed set.
