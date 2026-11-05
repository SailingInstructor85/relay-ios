#!/usr/bin/env python3
"""Sortiert die mit `xcresulttool export attachments` exportierten Dateien nach Testklasse und Namen um."""
import json, os, shutil, sys

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
try:
    manifest = json.load(open(os.path.join(src, "manifest.json")))
except OSError:
    print("kein manifest.json"); sys.exit(0)
n = 0
for t in manifest:
    cls = t.get("testIdentifier", "test").split("/")[0].replace("()", "")
    for a in t.get("attachments", []):
        f = a.get("exportedFileName")
        name = a.get("suggestedHumanReadableName", f)
        if not f or not os.path.exists(os.path.join(src, f)):
            continue
        ext = os.path.splitext(f)[1]
        base = name.rsplit("_0_", 1)[0] if "_0_" in name else os.path.splitext(name)[0]
        out = os.path.join(dst, f"{cls}__{t.get('testIdentifier','').split('/')[-1].replace('()','')}__{base}{ext}".replace(" ", "_"))
        shutil.copy(os.path.join(src, f), out)
        n += 1
print(n, "Anhaenge exportiert")
