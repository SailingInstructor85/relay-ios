"""Echter Durchlauf gegen das Gateway (nicht Teil der CI): dieselbe Codex-Unterhaltung vom Handy und vom PC aus.
Ruft den Daemon-Code direkt auf, ohne den Live-Dienst notifyd neu zu starten; der Live-Dienst sieht die Testsitzungen
trotzdem und kann sie dem Handy melden. Jede Nachricht verlangt nur ein Wort als Antwort, damit es wenig kostet
(acht kurze Codex-Züge). Aufruf (Venv des Gateways, nicht in tmux):

    env -u TMUX -u TMUX_PANE ~/relay/gateway/.venv/bin/python testing/gateway_codex_beide_geraete.py

Teil A, Start am Handy (Agenten-tmux-Sitzung wie bei „Neue Sitzung“): erste Nachricht an den Platzhalter, danach zwei
weitere Handy-Nachrichten nach fertiger Antwort (die dritte, während am PC ein Entwurf im Eingabefeld steht), dann
eine am PC getippte, dann wieder eine vom Handy. Teil B, Start am PC in einem Terminal ohne tmux (pty wie ein
Konsole-Fenster): am PC getippt, dann zwei Handy-Nachrichten. Geprüft wird: eine Sitzungs-ID je Teil, jede Nachricht
genau einmal im Verlauf, jede mit Antwort.

Ergebnis 2026-11-22 (Nachtbau 16:30, Codex 0.171): siehe docs/nachtlog.md und docs/pc-tmux.md."""

import asyncio, fcntl, json, os, pty, select, signal, struct, termios, threading, time
from pathlib import Path
ROOT = Path(os.environ.get("RELAY_TESTLAUF", os.path.expanduser("~/.local/state/agents/relay-nachtbau/testlauf")))
os.environ["NOTIFYD_STATE"] = str(ROOT / "state-codex")
os.environ["NOTIFYD_SOCKET"] = str(ROOT / "state-codex" / "sock")
(ROOT / "state-codex").mkdir(parents=True, exist_ok=True)
for v in ("TMUX", "TMUX_PANE"):
    os.environ.pop(v, None)
from notifyd import tmux
from notifyd.config import Config, CONFIG_PATH, resolve_binary
from notifyd.daemon import Daemon, RpcError, desk_terminal
from notifyd.launcher import launch_account
from notifyd.state import State

CWD = os.path.expanduser(os.environ.get("RELAY_CODEX_CWD", "~"))  # ein Ordner, dem Codex schon vertraut
out = {"schritte": []}
def step(s):
    out["schritte"].append(f"{time.strftime('%H:%M:%S')} {s}"); print(s, flush=True)

cfg = Config.load()
acct = cfg.account("x1")
LOCKS = Path(acct.home).expanduser() / "thread-writer-locks"

def ask(word):
    return f"Testlauf Relay. Antworte nur mit dem Wort {word}, ohne Werkzeuge."

def view(s):
    d = s.to_dict()
    return {"id": s.id, "alive": s.alive, "pane": s.pane, "tmux": s.tmux_session, "pid": s.pid, "state": s.state,
            "desk_terminal": desk_terminal(s), "queue_input": d.get("queue_input", False), "attachable": d["attachable"]}

def wait_reply(dm, find, word, limit=120):
    """Bis `word` als Antwort des Agenten im Verlauf steht. find(): (adapter, session) oder None."""
    end = time.time() + limit
    while time.time() < end:
        try:
            hit = find()
        except RpcError:
            hit = None
        if hit:
            msgs = hit[0].messages(hit[1]) or []
            if any(m["role"] == "assistant" and word in (m.get("text") or "") for m in msgs):
                return True
        time.sleep(2)
    return False

def count_user(dm, key, words):
    adapter, s = dm._find(key)
    msgs = adapter.messages(s) or []
    return {w: sum(1 for m in msgs if m["role"] == "user" and f"Wort {w}," in (m.get("text") or "")) for w in words}

async def phone(dm, label, params, word, find):
    try:
        res = await dm._send({**params, "text": ask(word)}, None)
    except RpcError as e:
        step(f"{label} FEHLER: abgelehnt: {e}")
        return {"gesendet": False, "fehler": str(e)}
    ok = wait_reply(dm, find, word)
    step(f"{label}: {res}, Antwort {word} da: {ok}")
    return {"gesendet": True, "how": res.get("how"), "antwort": ok}

async def part_a(dm):
    r = launch_account(acct, CWD, auto_trust=False)
    name = r.tmux_session
    pane = tmux.active_pane(name)
    step(f"A: tmux-Sitzung {name}, pane {pane}")
    await asyncio.sleep(8)
    ph = f"codex:x1:tmux-{name}"
    target = {"target": f"tmux:{name}"}
    succ = lambda: dm._successor(ph)
    a = out["a"] = {}
    try:
        a["handy_1_platzhalter"] = await phone(dm, "A Handy 1 (Platzhalter)", target, "ALPHA", succ)
        hit = succ()
        if not hit:
            step("A FEHLER: der Platzhalter hat keine echte Sitzung bekommen (Pane nicht zugeordnet)"); return
        key = hit[1].key
        a["sitzung_nach_erster_antwort"] = view(hit[1]); step(f"A: Sitzung {a['sitzung_nach_erster_antwort']}")
        find = lambda: dm._find(key)
        a["handy_2"] = await phone(dm, "A Handy 2", target, "BRAVO", find)
        # am PC steht ein unabgeschickter Entwurf im Eingabefeld, während das Handy sendet
        tmux._check("send-keys", "-t", pane, "-l", "ENTWURF-AM-PC"); await asyncio.sleep(1)
        a["handy_3_mit_pc_entwurf"] = await phone(dm, "A Handy 3 (Entwurf am PC)", target, "CHARLIE", find)
        a["pc_entwurf_steht_noch"] = "ENTWURF-AM-PC" in tmux.capture(pane, 40, escapes=False)
        step(f"A: Entwurf am PC steht noch: {a['pc_entwurf_steht_noch']}")
        tmux._check("send-keys", "-t", pane, "C-u"); await asyncio.sleep(0.5)
        # PC: wie an der Tastatur getippt
        tmux._check("send-keys", "-t", pane, "-l", ask("DELTA")); await asyncio.sleep(0.5); tmux._check("send-keys", "-t", pane, "Enter")
        a["pc_4"] = {"antwort": wait_reply(dm, find, "DELTA")}; step(f"A PC 4: Antwort DELTA da: {a['pc_4']['antwort']}")
        a["handy_5_per_key"] = await phone(dm, "A Handy 5 (per Schlüssel)", {"key": key}, "ECHO", find)
        a["sitzung_am_ende"] = view(dm._find(key)[1])
        a["nachrichten_im_verlauf"] = count_user(dm, key, ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO"])
        step(f"A: Verlauf {a['nachrichten_im_verlauf']}, Sitzung {a['sitzung_am_ende']}")
    finally:
        try: tmux.kill_session(name)
        except RuntimeError: pass
        step(f"A: tmux-Sitzung {name} beendet")

async def part_b(dm):
    before = {p.stem for p in LOCKS.glob("*.lock")}
    binary = resolve_binary(acct.binary)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(CWD)
        env = dict(os.environ, CODEX_HOME=str(Path(acct.home).expanduser()), TERM="xterm-256color", COLUMNS="120", LINES="40")
        os.execve(binary, [binary], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    def drain():
        while True:
            try:
                rr, _, _ = select.select([fd], [], [], 1)
                if rr:
                    b = os.read(fd, 65536)
                    if not b: break
                    if b"\x1b[6n" in b: os.write(fd, b"\x1b[1;1R")  # Cursorabfrage des TUI beantworten
            except OSError:
                break
    threading.Thread(target=drain, daemon=True).start()
    def reap():
        try: os.waitpid(pid, 0)
        except ChildProcessError: pass
    threading.Thread(target=reap, daemon=True).start()
    b = out["b"] = {}
    try:
        tid, end = None, time.time() + 30
        while time.time() < end and not tid:
            new = {p.stem for p in LOCKS.glob("*.lock")} - before
            tid = next(iter(new), None)
            await asyncio.sleep(1)
        if not tid:
            step("B FEHLER: keine neue Codex-Sitzung"); return
        key = f"codex:x1:{tid}"; step(f"B: pty-Sitzung {tid}, pid {pid}")
        await asyncio.sleep(5)
        find = lambda: dm._find(key)
        os.write(fd, ask("FOXTROT").encode()); await asyncio.sleep(0.5); os.write(fd, b"\r")
        b["pc_1"] = {"antwort": wait_reply(dm, find, "FOXTROT")}; step(f"B PC 1: Antwort FOXTROT da: {b['pc_1']['antwort']}")
        if not b["pc_1"]["antwort"]:
            return
        b["sitzung"] = view(dm._find(key)[1]); step(f"B: Sitzung {b['sitzung']}")
        b["handy_2"] = await phone(dm, "B Handy 2", {"key": key}, "GOLF", find)
        b["handy_3"] = await phone(dm, "B Handy 3", {"key": key}, "HOTEL", find)
        b["nachrichten_im_verlauf"] = count_user(dm, key, ["FOXTROT", "GOLF", "HOTEL"])
        step(f"B: Verlauf {b['nachrichten_im_verlauf']}")
    finally:
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
        await asyncio.sleep(2)
        try: os.kill(pid, signal.SIGKILL)
        except ProcessLookupError: pass
        step("B: pty-Sitzung beendet")

async def main():
    dm = Daemon(cfg, State(ROOT / "state-codex" / "s.db"), CONFIG_PATH)
    dm.prestart_router = False
    teil = os.environ.get("RELAY_TEIL", "ab")  # "a" oder "b": nur dieser Teil
    if "a" in teil: await part_a(dm)
    if "b" in teil: await part_b(dm)

asyncio.run(main())
(ROOT / f"codex-beide-ergebnis-{os.environ.get('RELAY_TEIL', 'ab')}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
print("ERGEBNIS " + json.dumps(out, ensure_ascii=False))
