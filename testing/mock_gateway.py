#!/usr/bin/env python3
"""Mock of the Relay `serve` gateway (PROTOCOL.md v2) for simulator UI tests.

JSON lines on stdin/stdout. All data is invented. Python 3 stdlib only.

Environment:
  MOCK_DIR   state and control directory (default /tmp/relaymock)

Control files in $MOCK_DIR/control (the UI tests or the CI script create them):
  offline        new connections end at once with an error; running ones are cut
  kick           running connections end (the file is removed by the first one)
  trigger_<n>    emit a live event once: finish_busy, new_input, notice, rueckfrage, send_request,
                 cloud, desktop_sleep, location, end_session
Logs: $MOCK_DIR/rpc.jsonl (every request received), $MOCK_DIR/mock.log (text).
"""
import base64, json, os, struct, sys, threading, time, zlib, hashlib, re

DIR = os.environ.get("MOCK_DIR", "/tmp/relaymock")
CTL = os.path.join(DIR, "control")
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(CTL, exist_ok=True)
STATE = os.path.join(DIR, "state.json")
OUT_LOCK = threading.Lock()
ST_LOCK = threading.Lock()
NOW0 = time.time()


def log(msg):
    try:
        with open(os.path.join(DIR, "mock.log"), "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} [{os.getpid()}] {msg}\n")
    except OSError:
        pass


def out(o):
    line = json.dumps(o, ensure_ascii=False)
    with OUT_LOCK:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def fixture(name):
    with open(os.path.join(HERE, "fixtures", name + ".json")) as f:
        return json.load(f)


# ---------------------------------------------------------------- virtual files

def make_png(w=640, h=360):
    rows = b""
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            stripe = ((x // 40) + (y // 40)) % 2
            r = int(40 + 180 * x / w)
            g = int(60 + 150 * y / h)
            b = 200 if stripe else 120
            row += bytes((r, g, b))
        rows += bytes(row)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def make_pdf(text="Relay Testbericht"):
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        None,
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    stream = f"BT /F1 24 Tf 72 760 Td ({text}) Tj 0 -40 Td /F1 12 Tf (Dies ist eine erfundene PDF-Datei fuer den UI-Test.) Tj ET".encode()
    objs[3] = b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream"
    buf = b"%PDF-1.4\n"
    offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(buf))
        buf += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    x = len(buf)
    buf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for o in offs:
        buf += b"%010d 00000 n \n" % o
    buf += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)
    return buf


W = "/home/dev/workspace/webapp"
README = f"""# Webapp

Kleine **Beispiel-App** fuer den Relay-Test.

## Aufbau

- `src/main.py` startet den Server
- `docs/diagramm.png` zeigt die Architektur
- [ ] Tests ergaenzen
- [x] Lizenz pruefen

| Modul | Zeilen | Status |
|---|---|---|
| main | 120 | ok |
| bench | 64 | in Arbeit |

```python
def main():
    print("hallo")
```
""".encode()
MAIN_PY = b'''import sys

def main(argv):
    """Startet den Server."""
    port = int(argv[1]) if len(argv) > 1 else 8080
    print(f"lausche auf {port}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
'''
FILES = {
    f"{W}/README.md": (README, "text/markdown", "text"),
    f"{W}/src/main.py": (MAIN_PY, "text/x-python", "text"),
    f"{W}/notes.txt": (b"Notizen\nZeile 2\nZeile 3\n", "text/plain", "text"),
    f"{W}/docs/diagramm.png": (make_png(), "image/png", "image"),
    f"{W}/docs/bericht.pdf": (make_pdf(), "application/pdf", "pdf"),
}


def file_obj(path):
    d, mime, kind = FILES[path]
    return {"path": path, "name": os.path.basename(path), "size": len(d), "mime": mime, "mtime": NOW0 - 3600, "kind": kind}


def resolve_path(p):
    p = p.replace("~/", "/home/dev/").replace("~", "/home/dev")
    if p in FILES:
        return p
    q = os.path.join(W, p)
    return q if q in FILES else None


# ---------------------------------------------------------------- data

ACCOUNTS = [
    {"alias": "c1", "tool": "claude", "label": "Claude #1", "home": "~/.claude", "logged_in": True},
    {"alias": "x1", "tool": "codex", "label": "Codex", "home": "~/.codex", "logged_in": True},
]
BASE = "claude:c1:"
K = {
    "busy": BASE + "11111111-aaaa-4000-8000-000000000001",
    "idle": BASE + "22222222-aaaa-4000-8000-000000000002",
    "ask": BASE + "33333333-aaaa-4000-8000-000000000003",
    "asks": "codex:x1:44444444-aaaa-4000-8000-000000000004",
    "exited": BASE + "55555555-aaaa-4000-8000-000000000005",
    "hib": BASE + "66666666-aaaa-4000-8000-000000000006",
    "closed": BASE + "77777777-aaaa-4000-8000-000000000007",
    "bg": BASE + "88888888-aaaa-4000-8000-000000000008",
    "menu": BASE + "99999999-aaaa-4000-8000-000000000009",
    "perm": BASE + "aaaaaaaa-aaaa-4000-8000-00000000000a",
    "panel": BASE + "bbbbbbbb-aaaa-4000-8000-00000000000b",
    "form": BASE + "cccccccc-aaaa-4000-8000-00000000000c",
    "pc": BASE + "dddddddd-aaaa-4000-8000-00000000000d",
    "desk": BASE + "eeeeeeee-aaaa-4000-8000-00000000000e",
}

QUESTION = {
    "question": "Welchen Tarif soll die Abrechnung verwenden?", "header": "Tarif",
    "options": [{"label": "Basis", "description": "guenstigster Tarif"}, {"label": "Plus", "description": "mit Support"},
                {"label": "Pro", "description": "alle Funktionen"}],
    "multi": False, "count": 2,
    "questions": [
        {"question": "Welchen Tarif soll die Abrechnung verwenden?", "header": "Tarif",
         "options": [{"label": "Basis", "description": "guenstigster Tarif"}, {"label": "Plus", "description": "mit Support"},
                     {"label": "Pro", "description": "alle Funktionen"}], "multi": False},
        {"question": "Welche Zusatzoptionen brauchst du?", "header": "Optionen",
         "options": [{"label": "Rechnung per Mail", "description": ""}, {"label": "Sammelrechnung", "description": ""},
                     {"label": "Export als CSV", "description": ""}], "multi": True},
    ],
}


def session_defs():
    n = time.time()
    return {
        K["busy"]: dict(title="Bench-Skript reparieren", cwd=f"{W}", state="busy", alive=True, attachable=True,
                        tmux_session="c1-webapp-3fa1", last_activity=n - 20, last_message="Ich laufe gerade die Benchmarks durch und fasse die Ergebnisse gleich zusammen.",
                        context={"tokens": 120000, "window": 1000000, "pct": 12, "level": "ok", "model": "claude-opus-5-5"}),
        K["idle"]: dict(title="API Refactoring", cwd=f"{W}", state="idle", alive=True, attachable=True, tmux_session="c1-webapp-7b2e",
                        last_activity=n - 600, last_message="Fertig. Die API ist umgebaut, alle 42 Tests laufen durch.",
                        context={"tokens": 310000, "window": 1000000, "pct": 31, "level": "large", "model": "claude-opus-5-5"}),
        K["ask"]: dict(title="Abrechnung einrichten", cwd="/home/dev/workspace/billing", state="needs_input", alive=True, attachable=True,
                       tmux_session="c1-billing-90cd", last_activity=n - 120, last_message="Ich brauche zwei Entscheidungen von dir.",
                       question=QUESTION),
        K["asks"]: dict(title="Datenbank migrieren", cwd="/home/dev/workspace/db", state="idle", alive=True, attachable=True,
                        tool="codex", alias="x1", label="Codex", tmux_session="x1-db-1a2b", last_activity=n - 1800,
                        last_message="Die Migration ist vorbereitet. Soll ich sie jetzt auf der Testdatenbank ausfuehren?",
                        asks=True, asks_text="1. Soll ich die Migration jetzt auf der Testdatenbank ausfuehren?"),
        K["exited"]: dict(title="Altes Experiment", cwd="/home/dev/workspace/lab", state="exited", alive=False, attachable=False,
                          tmux_session=None, last_activity=n - 86400 * 2, last_message="Experiment beendet."),
        K["hib"]: dict(title="Logs aufraeumen", cwd="/home/dev/workspace/ops", state="exited", alive=False, attachable=False, tmux_session=None,
                       last_activity=n - 86400, last_message="Ich habe die alten Logs gefunden.", hibernated=True, closed=True, closed_reason="idle"),
        K["closed"]: dict(title="Dokumentation pruefen", cwd="/home/dev/workspace/docs", state="exited", alive=False, attachable=False, tmux_session=None,
                          last_activity=n - 7200, last_message="Die Doku ist konsistent.", closed=True, closed_reason="user"),
        K["bg"]: dict(title="Nachtlauf Index", cwd="/home/dev/scratch", state="exited", alive=False, attachable=False, tmux_session=None,
                      last_activity=n - 5000, last_message="Index gebaut.", background=True),
        K["menu"]: dict(title="Modell wechseln", cwd=f"{W}", state="idle", alive=True, attachable=True, tmux_session="c1-webapp-m0de",
                        last_activity=n - 900, last_message="Waehle ein Modell im Menue."),
        K["perm"]: dict(title="Freigabe: Bash-Befehl", cwd=f"{W}", state="needs_input", alive=True, attachable=True, tmux_session="c1-webapp-pe4m",
                        last_activity=n - 60, last_message="Bash command: echo relay-probe > probe.txt"),
        K["panel"]: dict(title="Einstellungen offen", cwd=f"{W}", state="idle", alive=True, attachable=True, tmux_session="c1-webapp-pan1",
                         last_activity=n - 1500, last_message="Ein Dialog ist offen."),
        K["form"]: dict(title="Formular im Terminal", cwd=f"{W}", state="needs_input", alive=True, attachable=True, tmux_session="c1-webapp-f0rm",
                        last_activity=n - 300, last_message="Welche Groesse?"),
        # ein Terminal am PC zeigt die Sitzung (Sitzungsübergabe: die App fragt vor dem Tippen)
        K["pc"]: dict(title="Nachtlauf planen", cwd=f"{W}", state="idle", alive=True, attachable=True, tmux_session="c1-webapp-pcpc",
                      last_activity=n - 2400, last_message="Der Plan steht, ich warte auf dein Zeichen.", pc_attached=True),
        # am PC in einem Terminal ohne tmux: send wird abgelehnt, ausser mit move
        K["desk"]: dict(title="Skript ohne tmux", cwd=f"{W}", state="idle", alive=True, attachable=False, tmux_session=None,
                        last_activity=n - 3000, last_message="Das Skript laeuft im Terminal am PC."),
    }


SCREENS = {"menu": "model", "perm": "permission-prompt", "panel": "v308-usage", "form": "form", "ask": "question-multi"}


def full_session(key, d):
    parts = key.split(":", 2)
    s = {"key": key, "tool": d.get("tool", parts[0]), "alias": d.get("alias", parts[1]), "id": parts[2],
         "label": d.get("label", "Claude #1"), "cwd": d["cwd"], "title": d["title"], "state": d["state"], "alive": d["alive"],
         "attachable": d["attachable"], "tmux_session": d["tmux_session"], "last_activity": d["last_activity"],
         "last_message": d["last_message"], "duplicates": 1}
    for k in ("context", "question", "hibernated", "closed", "closed_reason", "background", "asks", "asks_text", "pc_attached"):
        if k in d:
            s[k] = d[k]
    return s


# ---------------------------------------------------------------- transcripts

def tmsg(i, role, text, tools=None, files=None):
    m = {"id": f"m{i}", "role": role, "text": text, "tools": tools or [], "ts": NOW0 - 7200 + i * 30}
    if files:
        m["files"] = files
    return m


RICH = [
    ("assistant", "## Zusammenfassung\n\nIch habe die **API** umgebaut. Die wichtigsten Punkte:\n\n1. Neue Route `/v2/items`\n2. Alte Route bleibt *deprecated*\n3. Tests ergaenzt\n\n> Hinweis: Die Datenbank wird nicht angefasst.\n\n- [x] Routen umgebaut\n- [ ] Doku ueberarbeiten\n\n---\n\nWeitere Infos stehen in der [Dokumentation](https://example.com/docs) und auf https://example.org/blog.",
     [{"name": "Read", "summary": "README.md", "path": f"{W}/README.md"}], [file_obj(f"{W}/README.md")]),
    ("user", "Zeig mir den Code und eine Tabelle der Laufzeiten.", None, None),
    ("assistant", "Hier der Startcode in `src/main.py`:\n\n```python\ndef main(argv):\n    port = int(argv[1]) if len(argv) > 1 else 8080\n    print(f\"lausche auf {port}\")\n    return 0\n```\n\n| Lauf | Dauer | Ergebnis |\n|---|---|---|\n| kalt | 1,8 s | ok |\n| warm | 0,4 s | ok |\n| Last | 3,2 s | langsam |\n\nDie Datei liegt unter `/home/dev/workspace/webapp/src/main.py:3`. Das Diagramm ist `/home/dev/workspace/webapp/docs/diagramm.png` und der Bericht `~/workspace/webapp/docs/bericht.pdf`.",
     [{"name": "Edit", "summary": "src/main.py", "path": f"{W}/src/main.py"}, {"name": "Bash", "summary": "pytest -q"}],
     [file_obj(f"{W}/src/main.py"), file_obj(f"{W}/docs/diagramm.png"), file_obj(f"{W}/docs/bericht.pdf")]),
    ("user", "Danke. Und was steht in den Notizen?", None, None),
    ("assistant", "In `notes.txt` stehen drei Zeilen. Ausserdem habe ich lange Zeilen getestet: Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua, ut enim ad minim veniam, quis nostrud exercitation.",
     [{"name": "Read", "summary": "notes.txt", "path": f"{W}/notes.txt"}, {"name": "Grep", "summary": "TODO"}], [file_obj(f"{W}/notes.txt")]),
]


def transcript_for(key, extra):
    msgs = []
    short = key in (K["exited"], K["hib"], K["closed"], K["bg"])
    n = 8 if short or key not in (K["idle"], K["busy"]) else 130
    for i in range(n):
        if i % 2 == 0:
            msgs.append(tmsg(i, "user", f"Frage {i // 2 + 1}: Bitte pruefe Schritt {i // 2 + 1} im Projekt."))
        else:
            tools = [{"name": "Bash", "summary": f"make step{i // 2 + 1}"}] if i % 4 == 1 else []
            msgs.append(tmsg(i, "assistant", f"Schritt {i // 2 + 1} ist erledigt. Ergebnis: alles in Ordnung.", tools))
    if key == K["idle"]:
        base = len(msgs)
        for j, (role, text, tools, files) in enumerate(RICH):
            msgs.append(tmsg(base + j, role, text, tools, files))
        msgs.append(tmsg(base + len(RICH), "system", "Kontext wurde automatisch gekuerzt."))
    elif key == K["busy"]:
        msgs.append(tmsg(len(msgs), "assistant", "Ich laufe gerade die Benchmarks durch.", [{"name": "Bash", "summary": "python bench.py --all"}]))
    else:
        msgs.append(tmsg(len(msgs), "assistant", "Waehle bitte eine Option." if key != K["ask"] else "Ich brauche zwei Entscheidungen von dir."))
    msgs.extend(extra)
    return msgs


# ---------------------------------------------------------------- state

def default_state():
    return {"seq": 100, "events": [], "sent": [], "extra_msgs": {}, "overrides": {}, "removed": [], "new": {}, "pinned": [],
            "profile": {"full_name": "Erika Mustermann", "first_name": "Erika", "last_name": "Mustermann", "city": "Musterstadt",
                        "postcode": "12345", "street": "Beispielweg", "house_number": "7", "country": "DE", "emails": ["erika@example.com"]},
            "config": {"overview": {"alias": "c1", "model": "haiku", "effort": "low"}, "poll_fallback_s": 15},
            "vocab": [["klaut", "Claude"]], "dirs": [], "fired": [], "uploads": {}, "closed_keys": {}}


def load_state():
    try:
        with open(STATE) as f:
            s = json.load(f)
        d = default_state()
        d.update(s)
        return d
    except (OSError, ValueError):
        return default_state()


def save_state(s):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f)
    os.replace(tmp, STATE)


def mutate(fn):
    with ST_LOCK:
        s = load_state()
        r = fn(s)
        save_state(s)
        return r


def add_event(typ, payload, persist=True):
    def f(s):
        ev = {"type": typ, "ts": time.time(), **payload}
        if persist:
            s["seq"] += 1
            ev["seq"] = s["seq"]
            s["events"].append(ev)
            s["events"] = s["events"][-200:]
        return ev
    ev = mutate(f)
    out(ev)
    return ev


def current_sessions(include_dormant=False, include_background=False):
    s = load_state()
    defs = session_defs()
    for k, v in s["new"].items():
        defs[k] = v
    for k, v in s["overrides"].items():
        if k in defs:
            defs[k].update(v)
    res = []
    for k, d in defs.items():
        if k in s["removed"] and not d.get("closed"):
            continue
        dormant = not d["alive"]
        if dormant and not include_dormant:
            continue
        if d.get("background") and not include_background:
            continue
        res.append(full_session(k, d))
    res.sort(key=lambda x: -x["last_activity"])
    return res


def find_session(key):
    for s in current_sessions(True, True):
        if s["key"] == key or (s.get("tmux_session") and key in ("tmux:" + s["tmux_session"],)):
            return s
    return None


# ---------------------------------------------------------------- rpc

class RpcError(Exception):
    pass


WATCH = set()
LAST_SEND_TEXT = {}


def ts_now():
    return time.time()


HOLDERS = {}  # session key -> "phone" | "desk" (Sitzungsübergabe; fehlt: offen)


def rpc_handover(p):
    s = find_session(p.get("key") or p.get("target", ""))
    if not s:
        raise RpcError("no such live session")
    to = p.get("to")
    if to is not None:
        if to not in ("phone", "desk", "open"):
            raise RpcError("to must be 'phone', 'desk' or 'open'")
        if to == "open":
            HOLDERS.pop(s["key"], None)
        else:
            HOLDERS[s["key"]] = to
    return {"holder": HOLDERS.get(s["key"], ""), "since": None, "pc_clients": 1, "session": s.get("tmux_session", "")}


def rpc_ping(p):
    return {}


def rpc_list_sessions(p):
    rows = current_sessions(bool(p.get("include_dormant")), bool(p.get("include_background")))[: int(p.get("limit", 100))]
    return {"sessions": [{**r, "holder": HOLDERS[r["key"]]} if r.get("key") in HOLDERS else r for r in rows]}


def rpc_accounts(p):
    return {"accounts": ACCOUNTS}


def rpc_transcript(p):
    key = p.get("key", "")
    s = find_session(key)
    if not s:
        raise RpcError("unknown session")
    st = load_state()
    msgs = transcript_for(s["key"], st["extra_msgs"].get(s["key"], []))
    if "from" in p:
        start = int(p["from"])
        end = int(p["before"]) if p.get("before") else len(msgs)
        page = msgs[start:end][:2000]
        return {"messages": page, "before": str(start) if start > 0 else None}
    end = int(p["before"]) if p.get("before") else len(msgs)
    lim = int(p.get("limit", 50))
    start = max(0, end - lim)
    r = {"messages": msgs[start:end], "before": str(start) if start > 0 else None}
    if not p.get("before"):
        r["context"] = {"tokens": (s.get("context") or {}).get("tokens", 90000), "model": "claude-opus-5-5"}
    return r


def rpc_transcript_search(p):
    q = str(p.get("query", "")).lower()
    if len(q) < 2:
        raise RpcError("query too short")
    s = find_session(p.get("key", ""))
    if not s:
        raise RpcError("unknown session")
    st = load_state()
    msgs = transcript_for(s["key"], st["extra_msgs"].get(s["key"], []))
    hits = []
    for i, m in enumerate(msgs):
        t = m["text"]
        if q in t.lower():
            at = t.lower().index(q)
            hits.append({"id": m["id"], "index": i, "role": m["role"], "ts": m["ts"], "snippet": t[max(0, at - 30): at + 60].replace("\n", " ")})
    hits.reverse()
    return {"matches": hits[: int(p.get("limit", 100))], "total_messages": len(msgs)}


def rpc_search_transcripts(p):
    q = str(p.get("query", "")).lower().split()
    hits = []
    for s in current_sessions(True, True):
        st = load_state()
        msgs = transcript_for(s["key"], st["extra_msgs"].get(s["key"], []))
        for m in reversed(msgs):
            if m["role"] in ("user", "assistant") and q and all(w in m["text"].lower() for w in q):
                at = m["text"].lower().index(q[0])
                hits.append({"session_key": s["key"], "tool": s["tool"], "alias": s["alias"], "role": m["role"],
                             "snippet": m["text"][max(0, at - 20): at + 80].replace("\n", " "), "ts": m["ts"]})
                break
    return {"hits": hits[:20]}


def rpc_screen(p):
    key = p.get("key") or p.get("target", "")
    s = find_session(key)
    if not s:
        raise RpcError("tmux session is gone")
    name = None
    for short, fx in SCREENS.items():
        if K[short] == s["key"]:
            name = fx
    menu = None
    if name and p.get("menu", True):
        menu = fixture(name)
        if name == "question-multi":
            menu = menu
    text = ("\x1b[1m╭─ Claude Code ─╮\x1b[0m\n> " + s["title"] + "\n\nDies ist ein erfundener Terminalinhalt.\n"
            "$ pytest -q\n.......... [100%]\n10 passed in 0.31s\n\n❯ ")
    if not p.get("escapes", True):
        text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    return {"text": text, "menu": menu, "holder": HOLDERS.get(s["key"], "")}


def rpc_running(p):
    s = find_session(p.get("key", ""))
    if s and s["key"] == K["busy"]:
        n = time.time()
        return {"running": [
            {"id": "t1", "kind": "agent", "label": "Benchmarks auswerten", "since": n - 200, "background": False, "activity": "Edit bench.py"},
            {"id": "t2", "kind": "shell", "label": "python bench.py --all", "since": n - 90, "background": True},
            {"id": "t3", "kind": "monitor", "label": "Logdatei beobachten", "since": n - 400, "background": True}],
            "state": "busy", "status": {"verb": "Computing", "elapsed": "1m 20s", "tokens": "4.2k tokens", "preview": ""}}
    return {"running": [], "state": s["state"] if s else "idle"}


def rpc_send(p):
    key = p.get("key") or p.get("target", "")
    s = find_session(key)
    if not s:
        raise RpcError("tmux session is gone" if key.startswith("tmux:") else "unknown session")
    if HOLDERS.get(s["key"]) == "desk":
        raise RpcError("session is held by the PC: take it over on the phone first (handover to: phone)")
    force = bool(p.get("force"))
    text = p.get("text")
    moved = False
    if s["alive"] and not s.get("tmux_session") and not p.get("target"):  # am PC in einem Terminal ohne tmux
        if not p.get("move"):
            raise RpcError("this session is open in a Desktop terminal outside tmux: reply there, or close it there and send again from the phone (it then resumes here)")

        def mv(st):
            st["overrides"].setdefault(s["key"], {}).update(tmux_session="c1-moved-0001", attachable=True)
        mutate(mv)
        moved = True
    if text and s["state"] == "busy" and not force and not p.get("target"):
        raise RpcError("session is busy")
    if not (text or p.get("keys") or p.get("steps")):
        raise RpcError("nothing to send: give text and/or keys")
    cid = p.get("client_id")

    def rec(st):
        st["sent"].append({"key": s["key"], "text": text, "keys": p.get("keys"), "steps": p.get("steps"), "client_id": cid, "ts": time.time()})
        if cid and any(x.get("client_id") == cid and x is not st["sent"][-1] for x in st["sent"]):
            st["sent"].pop()
            return False
        return True
    fresh = mutate(rec)
    if not fresh:
        return {"how": "duplicate"}
    if text or p.get("steps"):
        shown = text or " ".join(x if isinstance(x, str) else x.get("text", "") for x in p["steps"])
        threading.Thread(target=reply_to, args=(s["key"], shown), daemon=True).start()
    if moved:
        return {"how": "resumed in tmux c1-moved-0001 (moved from the PC terminal)"}
    return {"how": "tmux %" + s.get("tmux_session", "0") if s.get("tmux_session") else "resumed in tmux c1-resumed"}


WIND_DOWNS = {}  # job -> {"done", "items": {key: item}}
WD_PHASES = ["sending", "writing", "closing", "closed"]


def rpc_wind_down(p):
    keys = p.get("keys")
    if not isinstance(keys, list) or not keys or len(keys) > 50:
        raise RpcError("keys: 1-50 session keys")
    job = "wd%d" % (len(WIND_DOWNS) + 1)
    items = {}
    for k in keys:
        s = find_session(k)
        items[k] = {"key": k, "title": s["title"] if s else "", "alias": s["alias"] if s else "", "tool": s["tool"] if s else "",
                    "phase": "queued" if s else "error", "detail": "" if s else "no such session: " + k, "handover": "", "since": time.time()}
    WIND_DOWNS[job] = {"job": job, "done": False, "started": time.time(), "wait_s": int(p.get("wait_s") or 600), "items": items, "summary": ""}
    threading.Thread(target=wind_down_run, args=(job, p.get("text") or ""), daemon=True).start()
    return wind_down_view(job)


def wind_down_view(job):
    w = WIND_DOWNS[job]
    return {**w, "items": list(w["items"].values())}


def wind_down_run(job, text):
    w = WIND_DOWNS[job]
    for k, it in w["items"].items():
        if it["phase"] == "error":
            continue
        s = find_session(k)
        phases = (["waiting"] if s and s["state"] == "busy" else []) + WD_PHASES
        for ph in phases:
            time.sleep(0.5)
            it["phase"], it["since"] = ph, time.time()
            if ph == "closing":
                it["handover"] = "~/notes/%s.md" % it["title"].replace(" ", "-")
                mutate(lambda st: st["sent"].append({"key": k, "text": text, "wind_down": job}))
            if ph == "closed":
                def f(st, key=k):
                    st["overrides"].setdefault(key, {}).update(alive=False, state="exited", closed=True, closed_reason="user", tmux_session=None, attachable=False)
                    st["closed_keys"][key] = time.time()
                mutate(f)
            add_event("wind_down", {"job": job, "key": k, "title": it["title"], "phase": ph, "detail": it["detail"], "handover": it["handover"]})
    good = sum(1 for i in w["items"].values() if i["phase"] == "closed")
    w["summary"] = "%d von %d Sitzungen sauber beendet." % (good, len(w["items"]))
    w["done"] = True
    add_event("wind_down_done", {"job": job, "summary": w["summary"]})


def rpc_wind_down_status(p):
    job = p.get("job") or (next(reversed(WIND_DOWNS)) if WIND_DOWNS else None)
    if not job or job not in WIND_DOWNS:
        raise RpcError("unknown job")
    return wind_down_view(job)


def reply_to(key, text):
    def add(st):
        arr = st["extra_msgs"].setdefault(key, [])
        n = 1000 + len(arr)
        arr.append(tmsg(n, "user", text))
        return n
    n = mutate(add)
    emit_append(key, [tmsg(n, "user", text)])
    time.sleep(1.2)

    def add2(st):
        arr = st["extra_msgs"].setdefault(key, [])
        m = tmsg(1000 + len(arr), "assistant", f"Verstanden: {text[:80]}\n\nIch kuemmere mich darum.")
        arr.append(m)
        ov = st["overrides"].setdefault(key, {})
        ov.update(state="idle", last_message=m["text"][:200], last_activity=time.time())
        ov.pop("question", None)
        return m
    m = mutate(add2)
    emit_append(key, [m])
    s = find_session(key)
    if s:
        add_event("session_state", {"session": s, "prev_state": "busy", "reason": "hook:Stop", "origin": "user"})


def emit_append(key, msgs):
    if key in WATCH:
        out({"type": "transcript_append", "session_key": key, "messages": msgs})


def rpc_watch(p):
    WATCH.add(p.get("key", ""))
    return {}


def rpc_unwatch(p):
    WATCH.discard(p.get("key", ""))
    return {}


def rpc_close(p):
    key = p.get("key", "")
    s = find_session(key)
    if not s:
        raise RpcError("unknown session")

    def f(st):
        st["overrides"].setdefault(key, {}).update(alive=False, state="exited", closed=True, closed_reason="user", tmux_session=None, attachable=False)
        st["closed_keys"][key] = time.time()
    mutate(f)
    return {"closed": {"key": key}}


def rpc_reopen(p):
    key = p.get("key", "")
    if not find_session(key):
        raise RpcError("unknown session")

    def f(st):
        st["overrides"].setdefault(key, {}).update(alive=True, state="idle", closed=False, hibernated=False, tmux_session="c1-reopened-01", attachable=True)
        st["overrides"][key].pop("closed_reason", None)
    mutate(f)
    s = find_session(key)
    add_event("session_started", {"session": s})
    return {"tmux_session": "c1-reopened-01", "target": "tmux:c1-reopened-01", "alias": "c1"}


def rpc_kill(p):
    key = p.get("key", "")
    mutate(lambda st: st["removed"].append(key))
    s = find_session(key)
    return {}


def rpc_set_pinned(p):
    mutate(lambda st: st.__setitem__("pinned", p.get("keys", [])))
    return {"pinned": len(p.get("keys", []))}


def rpc_session_done(p):
    key = p.get("key", "")
    mutate(lambda st: st["overrides"].setdefault(key, {}).update(asks=False, asks_text=""))
    add_event("session_done", {"session_key": key})
    return {"cleared": True}


def rpc_session_seen(p):
    return {}


DIRS = [("/home/dev/workspace/webapp", True), ("/home/dev/workspace/billing", True), ("/home/dev/workspace/db", True),
        ("/home/dev/workspace/docs", False), ("/home/dev/workspace/ops", False), ("/home/dev/scratch", False)]


def rpc_recent_dirs(p):
    return {"dirs": [{"path": d, "last_used": time.time() - 3600 * (i + 1), "tools": ["claude"]} for i, (d, _) in enumerate(DIRS)]}


def rpc_find_dirs(p):
    terms = str(p.get("query", "")).lower().split()
    st = load_state()
    allp = [d for d, _ in DIRS] + st["dirs"]
    res = [{"path": d, "display": d.replace("/home/dev/", "~/"), "is_git": dict(DIRS).get(d, False), "recent": False}
           for d in allp if all(t in d.lower() for t in terms)]
    return {"dirs": res[: int(p.get("limit", 50))], "indexed": len(allp), "building": False}


def rpc_list_dirs(p):
    path = str(p.get("path", "~")).replace("~", "/home/dev")
    st = load_state()
    allp = [d for d, _ in DIRS] + st["dirs"]
    kids = {}
    for d in allp:
        if d.startswith(path.rstrip("/") + "/"):
            name = d[len(path.rstrip("/")) + 1:].split("/")[0]
            kids[name] = path.rstrip("/") + "/" + name
    dirs = [{"name": n, "path": pth, "is_git": dict(DIRS).get(pth, False)} for n, pth in sorted(kids.items())]
    parent = None if path == "/" else (os.path.dirname(path.rstrip("/")) or "/")
    return {"path": path, "parent": parent, "dirs": dirs}


def rpc_mkdir(p):
    path = str(p.get("path", ""))
    if not path.startswith("/"):
        path = "/home/dev/" + path.lstrip("~/")
    mutate(lambda st: st["dirs"].append(path))
    return {"path": path}


def rpc_launch(p):
    alias = p.get("alias", "c1")
    if alias == "auto":
        alias = "c1"
    cwd = str(p.get("cwd", "/home/dev"))
    n = hashlib.md5(f"{time.time()}".encode()).hexdigest()
    tool = "codex" if alias == "x1" else "claude"
    key = f"{tool}:{alias}:{n[:8]}-new0-4000-8000-{n[8:20]}"
    tmux = f"{alias}-{os.path.basename(cwd)}-{n[:4]}"
    title = p.get("name") or (str(p.get("prompt", ""))[:40] or "Neue Sitzung")
    d = dict(title=title, cwd=cwd, state="idle", alive=True, attachable=True, tmux_session=tmux, last_activity=time.time(),
             last_message="Sitzung gestartet.", tool=tool, alias=alias, label="Codex" if tool == "codex" else "Claude #1")
    mutate(lambda st: (st["new"].__setitem__(key, d), st["sent"].append({"launch": {k: p.get(k) for k in ("alias", "cwd", "prompt", "name")}})))
    add_event("session_started", {"session": full_session(key, d)})
    return {"tmux_session": tmux, "target": "tmux:" + tmux}


def rpc_memory(p):
    base = {"total_mb": 31800, "available_mb": 9800, "swap_total_mb": 8192, "swap_used_mb": 1200, "cpu_pct": 23.5, "load1": 1.8, "cpus": 12}
    if p.get("summary"):
        return {**base, "summary": True}
    st = load_state()
    sess = []
    for s in current_sessions():
        sess.append({"key": s["key"], "title": s["title"], "alias": s["alias"], "tool": s["tool"], "cwd": s["cwd"], "state": s["state"],
                     "closable": s["state"] != "needs_input", "mb": 300 + (hash(s["key"]) % 900), "swap_mb": 0 if s["state"] == "busy" else 40, "pids": [1000 + len(sess)]})
    closed = [{"key": K["hib"], "title": "Logs aufraeumen", "alias": "c1", "tool": "claude", "id": K["hib"].split(":")[2], "cwd": "/home/dev/workspace/ops",
               "closed_at": time.time() - 3600, "mb": 410, "reason": "idle", "idle_h": 14, "swap_mb": 100},
              {"key": K["closed"], "title": "Dokumentation pruefen", "alias": "c1", "tool": "claude", "id": K["closed"].split(":")[2], "cwd": "/home/dev/workspace/docs",
               "closed_at": time.time() - 7200, "mb": 260, "reason": "user"}]
    return {**base, "sessions": sess, "others": [{"name": "firefox", "mb": 2100, "swap_mb": 300, "count": 14}, {"name": "node", "mb": 850, "swap_mb": 0, "count": 3}], "closed": closed}


def rpc_usage(p):
    n = time.time()
    return {"accounts": [
        {"alias": "c1", "tool": "claude", "label": "Claude #1", "plan": "Max 20x", "error": "usage helper unavailable: claude-pool not found", "checked_at": n,
         "windows": [],
         "extras": {"as_of": n, "cloud_credit": {"limit": 100.0, "used": 37.5, "left": 62.5, "currency": "USD", "expires_at": n + 86400 * 20, "locked": False},
                    "extra_usage": {"enabled": True, "currency": "EUR", "used": 12.3, "limit": 50.0, "balance": 37.7, "auto_reload": False, "reason": ""},
                    "by_product": [{"name": "Claude Code", "pct": 41, "resets_at": n + 86400 * 3}, {"name": "Claude Design", "pct": 4, "resets_at": n + 86400 * 3}],
                    "scoped": [{"name": "Opus", "pct": 52, "resets_at": n + 86400 * 3}]}},
        {"alias": "x1", "tool": "codex", "label": "Codex", "plan": "Pro", "error": "", "checked_at": n,
         "windows": [{"name": "5h", "pct": 62, "resets_at": n + 7200, "forecast": {"runs_out_at": n + 3600}},
                     {"name": "Woche", "pct": 35, "resets_at": n + 86400 * 4, "forecast": {"unused_at_reset_pct": 28}}]},
    ]}


def rpc_cloud_sessions(p):
    return cloud_payload()


def cloud_payload():
    n = time.time()
    return {"sessions": [
        {"id": "cs1", "alias": "c1", "title": "Release vorbereiten", "repo": "dev/webapp", "branch": "main", "state": "waiting",
         "question": "Soll ich den Changelog automatisch schreiben?", "detail": "", "cost_usd": 1.84, "model": "opus", "created_at": n - 7200, "last_at": n - 300, "unread": True, "url": "https://claude.ai/code/session_demo1"},
        {"id": "cs2", "alias": "c1", "title": "Linter-Warnungen beheben", "repo": "dev/billing", "branch": "fix/lint", "state": "running", "question": "", "detail": "Aendert 4 Dateien", "cost_usd": 0.42, "model": "sonnet", "created_at": n - 3600, "last_at": n - 60, "unread": False, "url": "https://claude.ai/code/session_demo2"},
        {"id": "cs3", "alias": "c1", "title": "Typo-Korrektur", "repo": "dev/docs", "branch": "docs/typo", "state": "done", "question": "", "detail": "", "cost_usd": 0.1, "model": "haiku", "created_at": n - 86400, "last_at": n - 80000, "unread": False, "url": "https://claude.ai/code/session_demo3"}],
        "checked_at": n}


def rpc_digest(p):
    n = time.time()
    return {"title": "Das war los", "text": "In den letzten 12 Stunden: 2 Sitzungen fertig, 1 wartet auf dich.",
            "data": {"since": n - 43200,
                     "finished": [{"key": K["idle"], "title": "API Refactoring", "alias": "c1", "at": n - 600, "last_message": "Fertig. Alle Tests laufen.", "now": "idle"},
                                  {"key": K["asks"], "title": "Datenbank migrieren", "alias": "x1", "at": n - 1800, "last_message": "Migration vorbereitet.", "now": "idle"}],
                     "waiting": [{"key": K["ask"], "title": "Abrechnung einrichten", "alias": "c1", "since": n - 120, "question": "Welchen Tarif?"}],
                     "closed": [{"key": K["hib"], "title": "Logs aufraeumen", "alias": "c1", "reason": "idle", "mb": 410, "at": n - 3600}],
                     "usage": [], "memory": {}}}


def rpc_session_tokens(p):
    n = time.time()
    sess = []
    for i, (k, t) in enumerate([(K["idle"], "API Refactoring"), (K["busy"], "Bench-Skript reparieren"), (K["ask"], "Abrechnung einrichten")]):
        sess.append({"key": k, "alias": "c1", "id": k.split(":")[2], "title": t, "cwd": W, "member": None, "calls": 120 - i * 30, "subagent_calls": 10,
                     "input": 90000 - i * 20000, "cache_read": 4_200_000 - i * 1_000_000, "cache_write": 310000, "output": 52000 - i * 10000,
                     "weighted": 1_800_000 - i * 500_000, "last_at": n - 600 * (i + 1), "alive": True})
    tot = {"calls": 300, "input": 200000, "cache_read": 9_000_000, "cache_write": 700000, "output": 100000, "weighted": 3_600_000}
    return {"days": int(p.get("days", 7)), "since": n - 7 * 86400, "generated": n, "count": len(sess), "sessions": sess, "accounts": {"c1": tot}, "members": {}, "all": tot}


def rpc_ask(p, rid=None):
    q = str(p.get("text", ""))
    reply = f"Gern. Du hast gefragt: {q}\n\nIm Moment laufen vier Sitzungen: eine arbeitet, eine wartet auf dich. Soll ich etwas starten?"
    if p.get("stream") and rid:
        for chunk in re.findall(r".{1,14}", reply, re.S):
            out({"type": "rpc_progress", "id": rid, "delta": chunk})
            time.sleep(0.12)
    return {"text": reply, "sessions": [], "timing": {"first_text_ms": 900, "tools": [], "total_ms": 2400, "turns": 1}}


def rpc_voice_vocab(p):
    st = load_state()
    return {"terms": ["Relay", "Webapp", "Abrechnung", "notifyd"], "corrections": st["vocab"]}


def rpc_voice_vocab_add(p):
    line = f"{p.get('heard')} => {p['meant']}" if p.get("heard") else p.get("meant", "")
    if p.get("heard"):
        mutate(lambda st: st["vocab"].append([p["heard"], p["meant"]]))
    return {"added": line}


def rpc_voice_timing(p):
    return {}


def rpc_jarvis_warm(p):
    return {"running": True}


def rpc_speak_summary(p):
    return {"text": "Die Sitzung ist fertig. Alle Tests laufen durch.", "how": "cache"}


def rpc_clean_warm(p):
    return {"loaded": True}


def rpc_clean_dictation(p):
    return {"text": str(p.get("text", "")).strip()}


def rpc_get_config(p):
    return load_state()["config"]


def rpc_set_config(p):
    def f(st):
        o = st["config"]["overview"]
        for k in ("alias", "model", "effort"):
            if "overview_" + k in p:
                o[k] = p["overview_" + k]
        return st["config"]
    return mutate(f)


def rpc_power_status(p):
    return {"sessions": 6, "tasks": 3, "uptime_s": 190000, "reopen": True,
            "busy": [{"key": K["busy"], "title": "Bench-Skript reparieren", "alias": "c1"}]}


def rpc_power_off(p):
    mutate(lambda st: st["sent"].append({"power_off": p}))
    return {}


def rpc_standby(p):
    mutate(lambda st: st["sent"].append({"standby": p}))
    return {}


def rpc_profile_get(p):
    return {"profile": load_state()["profile"], "updated_at": time.time()}


def rpc_profile_set(p):
    mutate(lambda st: st.__setitem__("profile", p.get("profile", {})))
    return {"profile": p.get("profile", {}), "updated_at": time.time()}


def rpc_app_log(p):
    mutate(lambda st: st["sent"].append({"app_log": p.get("entries")}))
    return {"stored": len(p.get("entries", []))}


def rpc_phone_request_status(p):
    return {"status": "pending"}


def rpc_send_result(p):
    mutate(lambda st: st["sent"].append({"send_result": p}))
    add_event("send_resolved", {"request_id": p.get("request_id"), "ok": p.get("ok"), "error": p.get("error")})
    return {}


def rpc_confirm(p):
    mutate(lambda st: st["sent"].append({"confirm": p}))
    return {"result": "ok" if p.get("ok") else "denied"}


def rpc_location_result(p):
    return {}


def rpc_inbox_put(p):
    return {"stored": len(p.get("items", [])), "duplicates": 0}


def rpc_file_info(p):
    path = resolve_path(str(p.get("path", "")))
    if not path:
        raise RpcError("refused: no such file")
    return file_obj(path)


def rpc_file_get(p):
    path = resolve_path(str(p.get("path", "")))
    if not path:
        raise RpcError("refused: no such file")
    data, mime, kind = FILES[path]
    off = int(p.get("offset", 0))
    ln = min(int(p.get("length", 524288)), 524288)
    name = os.path.basename(path)
    if p.get("thumb") and kind == "image":
        return {"data_b64": base64.b64encode(data).decode(), "offset": 0, "size": len(data), "eof": True, "mime": "image/png", "name": name, "mtime": NOW0 - 3600, "thumb": True}
    chunk = data[off: off + ln]
    return {"data_b64": base64.b64encode(chunk).decode(), "offset": off, "size": len(data), "eof": off + len(chunk) >= len(data), "mime": mime, "name": name, "mtime": NOW0 - 3600}


def rpc_upload_begin(p):
    uid = hashlib.md5(f"{time.time()}{p.get('name')}".encode()).hexdigest()[:10]
    mutate(lambda st: st["uploads"].__setitem__(uid, {"name": p.get("name", "datei"), "size": p.get("size", 0), "got": 0}))
    return {"upload_id": uid}


def rpc_upload_chunk(p):
    raw = base64.b64decode(p.get("data_b64", ""))

    def f(st):
        u = st["uploads"].get(p.get("upload_id"))
        if not u:
            raise RpcError("unknown upload")
        u["got"] += len(raw)
        return u["got"]
    return {"received": mutate(f)}


def rpc_upload_end(p):
    def f(st):
        u = st["uploads"].pop(p.get("upload_id"), None)
        if not u:
            raise RpcError("unknown upload")
        path = f"/home/dev/.local/share/notifyd/uploads/2026-11-05/{u['name']}"
        st["sent"].append({"upload": {"name": u["name"], "size": u["got"], "path": path}})
        return {"path": path, "size": u["got"]}
    return mutate(f)


def rpc_hibernate(p):
    return {"mode": "dry-run", "candidates": [], "skipped": [], "closed": []}


def rpc_notices(p):
    return {}


METHODS = {k[4:]: v for k, v in list(globals().items()) if k.startswith("rpc_") and k != "rpc_ask"}


def handle_rpc(o):
    rid, method, params = o.get("id"), o.get("method", ""), o.get("params") or {}
    try:
        line = json.dumps({"ts": time.time(), "method": method, "params": params}, ensure_ascii=False)[:4000] + "\n"
        for fn in ("rpc.jsonl", "rpc-all.jsonl"):
            with open(os.path.join(DIR, fn), "a") as f:
                f.write(line)
    except OSError:
        pass
    try:
        if method == "ask":
            res = rpc_ask(params, rid)
        elif method in METHODS:
            res = METHODS[method](params)
        else:
            raise RpcError(f"unknown rpc {method!r}")
        out({"type": "rpc_result", "id": rid, "ok": True, "result": res})
    except RpcError as e:
        out({"type": "rpc_result", "id": rid, "ok": False, "error": str(e)})
    except Exception as e:  # noqa
        log(f"rpc {method} crashed: {e!r}")
        out({"type": "rpc_result", "id": rid, "ok": False, "error": f"internal error: {e}"})


# ---------------------------------------------------------------- live events

def trigger(name):
    if name == "finish_busy":
        def f(st):
            st["overrides"].setdefault(K["busy"], {}).update(state="idle", last_message="Die Benchmarks sind durch: 12 % schneller als vorher.", last_activity=time.time())
        mutate(f)
        add_event("session_state", {"session": find_session(K["busy"]), "prev_state": "busy", "reason": "hook:Stop", "origin": "user"})
    elif name == "new_input":
        def f(st):
            st["overrides"].setdefault(K["idle"], {}).update(state="needs_input", last_message="Darf ich die alte Route loeschen?", last_activity=time.time())
        mutate(f)
        add_event("session_state", {"session": find_session(K["idle"]), "prev_state": "idle", "reason": "hook:Notification",
                                     "message": "Darf ich die alte Route loeschen?"})
    elif name == "notice":
        add_event("notice", {"title": "Backup braucht neuen Login", "text": "Der naechtliche Backup-Job meldet: Anmeldung abgelaufen. Mehr Infos unter https://example.com/backup", "source": "backup", "tag": "backup"})
    elif name == "rueckfrage":  # an agent's question while the user is away (~/.agents/bin/rueckfrage neu)
        add_event("notice", {"title": "Rückfrage R1 · relay-ios",
                             "text": "Soll ich die alte Route löschen?\nKontext: Die Route wird seit 2024 nicht mehr genutzt.\nEmpfehlung: ja",
                             "source": "relay-ios", "tag": "rueckfrage:relay-ios:R1"})
    elif name == "send_request":
        add_event("send_request", {"request_id": "req-1", "kind": "mail", "executor": "desktop", "text": "Hallo Frau Muster,\n\nanbei die Rechnung.", "summary": "E-Mail an frau@example.com senden", "requested_by": "Jarvis", "expires_at": time.time() + 3600})
    elif name == "cloud":
        out({"type": "cloud_sessions", **cloud_payload()})
    elif name == "desktop_sleep":
        add_event("desktop_sleep", {"at": time.time()})
    elif name == "location":
        add_event("location_request", {"request_id": "loc-1", "reason": "Testanfrage", "expires_at": time.time() + 600})
    elif name == "end_session":
        def f(st):
            st["overrides"].setdefault(K["asks"], {}).update(alive=False, state="exited", tmux_session=None)
        mutate(f)
        add_event("session_ended", {"session_key": K["asks"], "session": find_session(K["asks"]), "by_user": False})


def watcher():
    while True:
        time.sleep(0.5)
        try:
            names = os.listdir(CTL)
        except OSError:
            continue
        if "offline" in names or "kick" in names:
            if "kick" in names:
                try:
                    os.remove(os.path.join(CTL, "kick"))
                except OSError:
                    pass
            log("cut by control file")
            os._exit(3)
        for n in names:
            if n.startswith("trigger_"):
                try:
                    os.remove(os.path.join(CTL, n))
                except OSError:
                    continue
                log("trigger " + n)
                trigger(n[8:])


def main():
    if os.path.exists(os.path.join(CTL, "offline")):
        sys.stderr.write("mock gateway offline\n")
        sys.exit(3)
    log(f"start cmd={os.environ.get('SSH_ORIGINAL_COMMAND')}")
    cmd = os.environ.get("SSH_ORIGINAL_COMMAND", "serve").split()
    if cmd and cmd[0] != "serve":
        sys.stderr.write(f"mock: only serve is supported, got {cmd[0]}\n")
        sys.exit(1)
    line = sys.stdin.readline()
    if not line:
        return
    hello = json.loads(line)
    since = int(hello.get("since_seq", 0))
    pinned = hello.get("pinned", [])
    log(f"hello since={since} pinned={len(pinned)} client={hello.get('client')}")
    st = load_state()
    for ev in st["events"]:
        if ev["seq"] > since:
            out({**ev, "replay": True})
    sess = current_sessions()
    st = load_state()
    out({"type": "hello_ok", "seq": st["seq"], "server_version": 2, "sessions": sess, "accounts": ACCOUNTS,
         "config": {"avatars": {}, "voice": "local"}, "app": None})
    threading.Thread(target=watcher, daemon=True).start()
    out({"type": "cloud_sessions", **cloud_payload()})

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            o = json.loads(raw)
        except ValueError:
            continue
        if o.get("type") == "rpc":
            threading.Thread(target=handle_rpc, args=(o,), daemon=True).start()
    log("stdin closed")


if __name__ == "__main__":
    main()
