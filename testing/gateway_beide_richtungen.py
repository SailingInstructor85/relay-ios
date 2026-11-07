"""Echter Durchlauf gegen das Gateway (nicht Teil der CI): Handy->PC und PC->Handy, einmal in einer Agenten-tmux-Sitzung,
einmal in einem Terminal ohne tmux (pty wie ein Konsole-Fenster). Ruft den Daemon-Code direkt auf, ohne den Live-Dienst
notifyd neu zu starten; der Live-Dienst sieht die Testsitzungen trotzdem (Registry) und kann sie dem Handy melden.
Modell haiku, damit es wenig kostet. Aufruf (Venv des Gateways, nicht in tmux):

    env -u TMUX -u TMUX_PANE ~/relay/gateway/.venv/bin/python testing/gateway_beide_richtungen.py

Ergebnis 2026-11-07 (Nachtbau 08:53, Gateway a3218d9): in tmux kommen beide Richtungen an (Text im Transkript, Antwort
HANDY-OK, Watch-Schleife liefert den am PC getippten Text), ohne tmux kommt PC->Handy an, Handy->PC wird mit
"outside tmux" abgelehnt. Siehe docs/nachtlog.md und docs/pc-tmux.md."""

import asyncio, fcntl, glob, json, os, pty, select, signal, struct, sys, termios, threading, time
from pathlib import Path
ROOT = Path(os.environ.get("RELAY_TESTLAUF", os.path.expanduser("~/.local/state/agents/relay-nachtbau/testlauf")))
os.environ["NOTIFYD_STATE"] = str(ROOT / "state2")
os.environ["NOTIFYD_SOCKET"] = str(ROOT / "state2" / "sock")
(ROOT / "state2").mkdir(parents=True, exist_ok=True)
for v in ("TMUX", "TMUX_PANE"):
    os.environ.pop(v, None)
from notifyd import trust, tmux
from notifyd.config import Config, CONFIG_PATH
from notifyd.daemon import Daemon, RpcError, desk_terminal
from notifyd.launcher import launch_account
from notifyd.state import State

out = {"schritte": []}
def step(s):
    out["schritte"].append(f"{time.strftime('%H:%M:%S')} {s}"); print(s, flush=True)

cfg = Config.load()
acct = cfg.account("c1")

def registry_for(pred):
    for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            d = json.loads(open(f).read())
        except Exception:
            continue
        try:
            if pred(int(d.get("pid", 0))):
                return d
        except Exception:
            pass
    return None

def wait_registry(pred, limit=90):
    end = time.time() + limit
    while time.time() < end:
        d = registry_for(pred)
        if d and d.get("sessionId"):
            return d
        time.sleep(1)
    return None

def wait_idle_after_busy(pred, limit=150):
    seen_busy = False; end = time.time() + limit
    while time.time() < end:
        d = registry_for(pred) or {}
        if d.get("status") == "busy": seen_busy = True
        if seen_busy and d.get("status") != "busy": return True
        time.sleep(1)
    return False

def wait_messages(dm, key, text, limit=150):
    """Was die Watch-Schleife ans Handy schicken wuerde: adapter.messages, bis der Text als user-Nachricht da ist und
    danach eine Agentenantwort steht."""
    end = time.time() + limit; got_user = None; reply = None
    while time.time() < end:
        try:
            adapter, s = dm._find(key)
        except RpcError:
            time.sleep(2); continue
        msgs = adapter.messages(s) or []
        for i, m in enumerate(msgs):
            if m["role"] == "user" and text in (m.get("text") or ""):
                got_user = i
            if got_user is not None and i > got_user and m["role"] == "assistant" and (m.get("text") or "").strip():
                reply = m["text"].strip()
        if reply: break
        time.sleep(2)
    return got_user is not None, reply

async def main():
    dm = Daemon(cfg, State(ROOT / "state2" / "s.db"), CONFIG_PATH)
    dm.prestart_router = False

    # ---------------- A: Agenten-tmux-Sitzung (wie vom Handy gestartet)
    cwd_a = ROOT / "mit-tmux"
    r = launch_account(acct, str(cwd_a), args=["--model", "haiku"], auto_trust=True)
    name = r.tmux_session
    pane = tmux.active_pane(name)
    step(f"A: tmux-Sitzung {name}, pane {pane}")
    d = wait_registry(lambda pid: tmux.pane_for_pid(pid) == pane)
    if not d:
        step("A FEHLER: keine Registry"); tmux.kill_session(name); return
    sid_a = d["sessionId"]; key_a = f"claude:c1:{sid_a}"
    step(f"A: Registry {sid_a}, status {d.get('status')}")
    time.sleep(5)
    adapter, s = dm._find(key_a)
    out["a_sitzung"] = {"alive": s.alive, "pane": s.pane, "tmux": s.tmux_session, "attachable": s.attachable, "pid": s.pid}
    step(f"A: Daemon sieht: {out['a_sitzung']}")
    # Handy -> PC: wie die App (liveTmux != nil -> target tmux:<name>)
    text_a1 = "Antworte nur mit dem Wort HANDY-OK-4712 und sonst nichts."
    try:
        res = await dm._send({"target": f"tmux:{name}", "text": text_a1}, None)
        step(f"A: send per target: {res}")
    except RpcError as e:
        step(f"A FEHLER send per target: {e}")
    got, reply = wait_messages(dm, key_a, text_a1)
    out["a_handy_zu_pc"] = {"text_im_transkript": got, "antwort": reply}
    step(f"A Handy->PC: Text im Transkript {got}, Antwort {reply!r}")
    # PC -> Handy: am PC getippt (send-keys wie eine Tastatur), dann was die Watch-Schleife liefern wuerde
    adapter, s = dm._find(key_a)
    w = {"adapter": adapter, "session": s, "seen": {m["id"]: __import__("notifyd.daemon", fromlist=["_digest"])._digest(m) for m in (adapter.messages(s) or [])}}
    text_a2 = "Antworte nur mit dem Wort PC-OK-4713 und sonst nichts."
    tmux._check("send-keys", "-t", pane, "-l", text_a2); time.sleep(0.5); tmux._check("send-keys", "-t", pane, "Enter")
    step("A: am PC getippt")
    end = time.time() + 150; new_user = False; new_reply = None
    while time.time() < end:
        for m in dm._watch_new(w):
            if m["role"] == "user" and text_a2 in (m.get("text") or ""): new_user = True
            if new_user and m["role"] == "assistant" and (m.get("text") or "").strip(): new_reply = m["text"].strip()
        if new_reply: break
        await asyncio.sleep(1)
    out["a_pc_zu_handy"] = {"watch_lieferte_text": new_user, "antwort": new_reply}
    step(f"A PC->Handy: Watch lieferte Text {new_user}, Antwort {new_reply!r}")
    # PC-Client anhaengen (Terminal am PC), list-clients pruefen, wieder loesen
    cpid, cfd = pty.fork()
    if cpid == 0:
        os.execvp("tmux", ["tmux", "attach-session", "-t", f"={name}"])
    fcntl.ioctl(cfd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    time.sleep(2)
    clients = tmux._run("list-clients", "-F", "#{client_tty}\t#{session_name}\t#{session_group}")
    out["a_clients_mit_pc"] = clients.strip().splitlines()
    out["a_attached_mit_pc"] = sorted(tmux.attached_sessions() or [])
    step(f"A: Clients mit PC-Terminal: {out['a_clients_mit_pc']}")
    os.kill(cpid, signal.SIGHUP); time.sleep(1)
    try: os.waitpid(cpid, 0)
    except ChildProcessError: pass
    out["a_clients_ohne_pc"] = tmux._run("list-clients", "-F", "#{client_tty}\t#{session_name}").strip().splitlines()
    step(f"A: Clients nach Loesen: {out['a_clients_ohne_pc']}")
    tmux.kill_session(name); step(f"A: tmux-Sitzung {name} beendet")

    # ---------------- B: Terminal ohne tmux (pty), wie `claude` in Konsole
    cwd_b = ROOT / "ohne-tmux2"
    trust.pretrust(acct, str(cwd_b))
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd_b)
        env = {k: v for k, v in os.environ.items() if not k.upper().startswith("CLAUDE")}
        env.update(TERM="xterm-256color", COLUMNS="120", LINES="40")
        os.execvpe("claude", ["claude", "--model", "haiku"], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    log = open(ROOT / "beide-pty.log", "ab")
    def drain():
        while True:
            try:
                rr, _, _ = select.select([fd], [], [], 1)
                if rr:
                    b = os.read(fd, 65536)
                    if not b: break
                    log.write(b); log.flush()
            except OSError:
                break
    threading.Thread(target=drain, daemon=True).start()
    def reap():
        try: os.waitpid(pid, 0)
        except ChildProcessError: pass
    threading.Thread(target=reap, daemon=True).start()
    d = wait_registry(lambda p: p == pid)
    if not d:
        step("B FEHLER: keine Registry"); os.kill(pid, signal.SIGKILL); return
    sid_b = d["sessionId"]; key_b = f"claude:c1:{sid_b}"
    step(f"B: pty-Sitzung {sid_b}, pid {pid}")
    time.sleep(5)
    text_b1 = "Antworte nur mit dem Wort PC-OK-4714 und sonst nichts."
    os.write(fd, text_b1.encode()); time.sleep(0.5); os.write(fd, b"\r")
    step("B: am PC getippt")
    got, reply = wait_messages(dm, key_b, text_b1)
    out["b_pc_zu_handy"] = {"text_im_transkript": got, "antwort": reply}
    step(f"B PC->Handy: Text im Transkript {got}, Antwort {reply!r}")
    adapter, s = dm._find(key_b)
    out["b_sitzung"] = {"alive": s.alive, "pane": s.pane, "tmux": s.tmux_session, "attachable": s.attachable, "pid": s.pid,
                        "desk_terminal": desk_terminal(s), "dict": {k: v for k, v in s.to_dict().items() if k in ("alive", "attachable", "tmux_session", "background")}}
    step(f"B: Daemon sieht: {out['b_sitzung']}")
    try:
        res = await dm._send({"key": key_b, "text": "Antworte nur mit HANDY-OK-4715."}, None)
        out["b_handy_zu_pc"] = {"gesendet": True, "res": res}
        step(f"B FEHLER: send ohne move nicht abgelehnt: {res}")
    except RpcError as e:
        out["b_handy_zu_pc"] = {"gesendet": False, "fehler": str(e)}
        step(f"B Handy->PC: abgelehnt: {e}")
    os.kill(pid, signal.SIGTERM); time.sleep(3)
    try: os.kill(pid, signal.SIGKILL)
    except ProcessLookupError: pass
    step("B: pty-Sitzung beendet")

asyncio.run(main())
(ROOT / "beide-ergebnis.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
print("ERGEBNIS " + json.dumps(out, ensure_ascii=False))
