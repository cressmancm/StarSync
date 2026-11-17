#!/bin/zsh
# Counts the App Store fields in listing.md that have a length limit.
#
# App Store Connect counts characters, not bytes, so "•" and "—" are one each.
# The fenced blocks are read in document order: promotional text,
# description, keywords, review notes.
cd "$(dirname "$0")"
python3 - <<'PY'
import re
text = open("listing.md", encoding="utf-8").read()
blocks = re.findall(r"```\n(.*?)\n```", text, re.S)
fields = [("Promotional text", 170), ("Description", 4000),
          ("Keywords", 100), ("Review notes", 4000)]
fine = True
for (name, limit), block in zip(fields, blocks):
    n = len(block)
    ok = n <= limit
    fine &= ok
    print(f"{'ok ' if ok else 'TOO LONG'} {name:<17} {n:>5} / {limit}")
for name, value, limit in [("Name", "StarSync", 30),
                           ("Subtitle", "Copy star ratings into Photos", 30),
                           ("Fallback name", "StarSync: Ratings to Photos", 30)]:
    ok = len(value) <= limit
    fine &= ok
    print(f"{'ok ' if ok else 'TOO LONG'} {name:<17} {len(value):>5} / {limit}")
kw = blocks[2].split(",")
dupes = {k for k in kw if kw.count(k) > 1}
banned = [k for k in kw if re.search(r"lightroom|adobe|starsync", k, re.I)]
if dupes or banned:
    fine = False
    print("keywords: duplicated", sorted(dupes), "trademarked or the app's own name", banned)
raise SystemExit(0 if fine else 1)
PY
