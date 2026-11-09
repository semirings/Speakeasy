"""Check one or more EBNF files as a single grammar.
Usage: python3 -I check_ebnf.py base.ebnf [d4m.ebnf blender.ebnf]
`X ::= ...` defines X. `X += ...` extends X, which must be defined with `::=`.
"""
import re, sys, collections
src = "\n".join(open(f, encoding="utf-8").read() for f in sys.argv[1:])
if src.count("(*") != src.count("*)"):
    print("UNBALANCED comments", src.count("(*"), src.count("*)"))
body = re.sub(r"\(\*.*?\*\)", "", src, flags=re.S)
body_nt = re.sub(r"'(?:[^'\\]|\\.)*'", " ", body)
body_nt = re.sub(r'\[(?:[^\]\\]|\\.)*\]', " ", body_nt)
defs = re.findall(r"^([A-Za-z][A-Za-z0-9]*)\s*::=", body_nt, flags=re.M)
exts = re.findall(r"^([A-Za-z][A-Za-z0-9]*)\s*\+=", body_nt, flags=re.M)
dups = [r for r, n in collections.Counter(defs).items() if n > 1]
print("rules:", len(defs), "extensions:", len(exts), "duplicates:", dups)
defined = set(defs)
bad_ext = sorted(set(e for e in exts if e not in defined))
print("extends an undefined rule:", bad_ext)
rhs = re.sub(r"^[A-Za-z][A-Za-z0-9]*\s*(::=|\+=)", " ", body_nt, flags=re.M)
used = set(re.findall(r"\b[A-Za-z][A-Za-z0-9]*\b", rhs))
print("undefined:", sorted(u for u in used if u not in defined))
unused = sorted(d for d in defined if d not in used and d != "script")
print("unreferenced:", unused)
for chunk in re.split(r";\s*\n", body_nt):
    if chunk.count("(") != chunk.count(")"):
        print("PAREN imbalance near:", chunk.strip()[:60])
