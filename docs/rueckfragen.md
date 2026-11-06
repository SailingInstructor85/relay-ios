# Rückfragen von Agenten als Push über Relay

Stand: 2026-11-06. Stellt ein Agent eine Rückfrage (`~/.agents/bin/rueckfrage neu`) oder schickt eine Meldung
(`rueckfrage meldung`), während Martin weg ist, soll sie als Push-Nachricht aufs iPhone kommen. Die Antwort soll
direkt zurück an `rueckfrage` gehen. Die App-Seite ist gebaut; der Aufruf im Skript `rueckfrage` (außerhalb dieses
Repos) ist unten nur vorgeschlagen.

## Was die App kann (ab 0.3.3)

Grundlage ist das vorhandene Gateway-Ereignis `notice` (`notifyd phone notify`, RPC `notice`, PROTOCOL.md
"Desktop → phone: notices"). Die App erkennt eine Rückfrage am `tag`:

| Feld | Rückfrage | Meldung |
|---|---|---|
| `tag` | `rueckfrage:<agent>:R<n>` | `meldung:<agent>:M<n>` |
| `title` | frei, z. B. `Rückfrage R1 · relay-ios` (leer: die App zeigt "Rückfrage R1 von relay-ios") | z. B. `Meldung M2 · relay-ios` |
| `text` | Frage, danach je eine eigene Zeile `Kontext: …` und `Empfehlung: …` (beide optional) | Text der Meldung |
| `source` | Agentenname | Agentenname |

Verhalten in der App (`C: Notify.swift` `Rueckfrage`, `A: NoticeView.swift`, `A: AppModel+Chat.swift`):

- Mitteilung mit Titel und Frage. Bei einer Rückfrage hat sie die Aktion "Antworten" (Textfeld) und, wenn eine
  Empfehlung dabei ist, "Ja (Empfehlung)". Die Antwort geht im Hintergrund zum PC (kurze eigene Verbindung); klappt
  das nicht, kommt eine Mitteilung "Antwort nicht angekommen" mit dem Antworttext.
- Ein Tipp auf die Mitteilung öffnet die Rückfrage unter "Hinweise": Frage, Kontext, Empfehlung, darunter das Feld
  "Antwort an <agent>" mit "Antworten" und "Ja (Empfehlung)". Eine beantwortete Rückfrage zeigt "Beantwortet: …" und
  wird beim Replay nicht erneut gemeldet. Meldungen (M…) werden nur gezeigt.
- Die Antwort geht als Eingangs-Element zum Gateway: RPC `inbox_put` mit `kind: "notification"` und einem Element
  `{"id": "rueckfrage|<agent>|R<n>|<ms>", "ts": <unix s>, "app": "rueckfrage", "app_label": "Rückfrage",
  "title": "<agent> R<n>", "text": "<Antwort>", "conversation": "<agent>", "has_reply": false}`. Das Gateway legt
  es unter `~/.local/share/notifyd/inbox/notification/<YYYY-MM-DD>.jsonl` ab (dedupliziert nach `id`) und liefert es
  über `notifyd phone inbox --kind notification --app rueckfrage`. Dafür ist am Gateway nichts zu ändern.

## Vorschlag für `~/.agents/bin/rueckfrage` (nicht umgesetzt)

1. `cmd_neu` und `cmd_meldung`: nach dem Schreiben der Datei, wenn Martin weg ist (`anwesenheit status` Exit 1),
   den Push anstoßen. Fehler dabei nur melden, nie abbrechen (die Datei im Vault bleibt der Hauptweg):

   ```python
   import subprocess, shutil
   NOTIFYD = os.path.expanduser("~/relay/gateway/.venv/bin/notifyd")

   def push(title: str, text: str, agent: str, tag: str) -> None:
       if not os.path.exists(NOTIFYD):
           return
       try:
           subprocess.run([NOTIFYD, "phone", "notify", "--title", title, "--text", text,
                           "--source", agent, "--tag", tag], check=False, capture_output=True, timeout=15)
       except (OSError, subprocess.TimeoutExpired) as e:
           print(f"Hinweis: Push nicht gesendet ({e})", file=sys.stderr)

   # in cmd_neu, nach schreiben(...):
   text = a.frage.strip()
   if a.kontext: text += f"\nKontext: {a.kontext.strip()}"
   if a.empfehlung: text += f"\nEmpfehlung: {a.empfehlung.strip()}"
   push(f"Rückfrage R{nr} · {slug(a.agent)}", text, slug(a.agent), f"rueckfrage:{slug(a.agent)}:R{nr}")

   # in cmd_meldung, nach schreiben(...):
   push(f"Meldung M{nr} · {slug(a.agent)}", a.text.strip(), slug(a.agent), f"meldung:{slug(a.agent)}:M{nr}")
   ```

2. `cmd_warten`: in jeder Runde zusätzlich den Eingang des Gateways prüfen und eine Antwort vom iPhone wie
   `rueckfrage antworten` eintragen (danach greift der bestehende Pfad über die Datei):

   ```python
   def antwort_vom_handy(agent: str, rid: str) -> str | None:
       try:
           out = subprocess.run([NOTIFYD, "phone", "inbox", "--kind", "notification", "--app", "rueckfrage",
                                 "--hours", "72", "--limit", "50"], capture_output=True, text=True, timeout=15).stdout
           items = json.loads(out or "[]")
       except (OSError, ValueError, subprocess.TimeoutExpired):
           return None
       for it in items:  # neueste zuerst
           if it.get("title") == f"{slug(agent)} {rid.upper()}" and it.get("text"):
               return it["text"].strip()
       return None

   # in der Schleife von cmd_warten, vor time.sleep(...):
   if q["status"] == "offen":
       t = antwort_vom_handy(a.agent, a.rid)
       if t:
           cmd_antworten(argparse.Namespace(agent=a.agent, rid=a.rid, text=t))
           continue
   ```

   Alternative ohne RPC: die JSONL-Dateien unter `~/.local/share/notifyd/inbox/notification/` der letzten drei Tage
   direkt lesen und nach `app == "rueckfrage"` filtern.

3. Offen zu entscheiden: ob auch der Assistent in der Claude-App (der die Vault-Datei liest) die Antwort aus dem
   Eingang sehen soll, damit beide Wege nicht auseinanderlaufen. Mit Schritt 2 trägt `rueckfrage warten` die Antwort
   in die Datei ein, sobald der wartende Agent sie abholt; der Assistent sieht sie dann als "beantwortet".

## Test

- RelayCore: `NotifyTests.testAgentQuestion` (Tag, Zerlegung in Frage, Kontext, Empfehlung, Antwort-Element, Antwort
  überlebt Replay und Speichern).
- Simulator: `InfoTests.test20_AgentQuestion` (Mock-Auslöser `trigger_rueckfrage`, Antwort im Hinweis, `inbox_put`
  beim Mock angekommen).
- Von Hand am PC, sobald das Skript den Push kann: `~/relay/gateway/.venv/bin/notifyd phone notify --title
  "Rückfrage R1 · test" --text "Soll ich weitermachen?\nEmpfehlung: ja" --source test --tag rueckfrage:test:R1`,
  dann am iPhone antworten und `notifyd phone inbox --kind notification --app rueckfrage` prüfen.
