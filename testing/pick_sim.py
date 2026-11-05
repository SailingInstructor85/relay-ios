#!/usr/bin/env python3
"""Gibt die UDID des neuesten verfügbaren iPhone-Pro-Simulators aus (iPhone 16 Pro bevorzugt bei gleicher iOS-Version)."""
import json, re, subprocess, sys

d = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
c = []
for rt, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    if not m:
        continue
    for x in devs:
        n = x["name"]
        if x.get("isAvailable") and "iPhone" in n and "Pro" in n and "Max" not in n:
            num = re.search(r"iPhone (\d+)", n)
            c.append((int(m.group(1)), int(m.group(2)), n == "iPhone 16 Pro", int(num.group(1)) if num else 0, n, x["udid"]))
if not c:
    sys.exit("kein iPhone Pro Simulator")
c.sort(reverse=True)
print(c[0][5])
sys.stderr.write("gewaehlt: %s (iOS %d.%d)\n" % (c[0][4], c[0][0], c[0][1]))
