import re, sys, collections
src = open(sys.argv[1], encoding="utf-8").read()
# strip comments (non-nested, but ensure balanced)
if src.count("(*") != src.count("*)"):
    print("UNBALANCED comments", src.count("(*"), src.count("*)"))
body = re.sub(r"\(\*.*?\*\)", "", src, flags=re.S)
# remove terminals and char classes
body_nt = re.sub(r"'(?:[^'\\]|\\.)*'", " ", body)
body_nt = re.sub(r'\[(?:[^\]\\]|\\.)*\]', " ", body_nt)
rules = re.findall(r"^([A-Za-z][A-Za-z0-9]*)\s*::=", body_nt, flags=re.M)
dups = [r for r, n in collections.Counter(rules).items() if n > 1]
print("rules:", len(rules), "duplicates:", dups)
defined = set(rules)
rhs = re.sub(r"^[A-Za-z][A-Za-z0-9]*\s*::=", " ", body_nt, flags=re.M)
used = set(re.findall(r"\b[A-Za-z][A-Za-z0-9]*\b", rhs))
undefined = sorted(u for u in used if u not in defined)
print("undefined:", undefined)
unused = sorted(d for d in defined if d not in used and d != "script")
print("unreferenced:", unused)
# paren balance per rule
for chunk in re.split(r";\s*\n", body_nt):
    if chunk.count("(") != chunk.count(")"):
        print("PAREN imbalance near:", chunk.strip()[:60])
    if chunk.count("'") % 2:
        pass
print("rules ending ';':", len(re.findall(r";\s*$", body_nt, flags=re.M)))
cmds = re.search(r"^command\s*::=(.*?);", body_nt, flags=re.S | re.M).group(1)
print("command alternatives:", len(re.findall(r"\b\w+Cmd\b", cmds)) + len(re.findall(r"\bbeep\b", cmds)))
