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

Seit 0.3.9 lassen sich offene Rückfragen auch im Sprachmodus beantworten (vorlesen, per Sprache antworten,
Kontrolle, „senden“). Die Antwort geht auf demselben Weg (`inbox_put`) zum PC. Details: `docs/sprachmodus.md`.

## Schließen auf allen Geräten und „Erledigt“ (ab 0.4.2)

Wahr ist der Stand am PC (die Dateien des Skripts `rueckfrage`), die App spiegelt ihn nur. Vertrag: PROTOCOL.md des
Gateways, Abschnitt „Rückfragen“ (Gateway ab 2026-11-24).

- Ereignis `rueckfrage_resolved {tag, answer, source, at}`: kommt nach jeder Antwort, von jedem Gerät und vom PC, und
  wird beim Verbinden nachgespielt. Die App setzt die Antwort an jedem offenen Hinweis mit diesem Tag und entfernt die
  Mitteilung. Die Karte in „Dein Zug“ und der Eintrag im Sprachmodus verschwinden damit (`C: Notify.swift`
  `Rueckfrage.resolve`).
- Abgleich nach jedem `hello_ok`: Die App schickt die Tags ihrer offenen Rückfragen an `rueckfrage_status`. Was dort
  `beantwortet` oder `unbekannt` ist, geht zu (`Rueckfrage.reconcile`). Kennt das Gateway den RPC nicht oder scheitert
  er, bleibt alles offen.
- „Erledigt“ (klein, auf der Karte in „Dein Zug“ und im Hinweis): schließt eine Rückfrage ohne Bearbeiten. Vorher
  fragt die App nach, weil der Agent am PC „(verworfen)“ als Antwort bekommt. Der Weg ist derselbe wie bei jeder
  Antwort (`inbox_put`).
- Antwort auf eine Rückfrage, die schon zu ist: Die App schickt nichts und zeigt „Schon beantwortet: …“. Kommt die
  Schließung, während die eigene Antwort unterwegs ist, gilt die Antwort vom PC.
- `notices.json` bleibt je Installation. Ob eine Rückfrage offen ist, entscheidet aber nie mehr nur der lokale Stand.

## Blatt „Rückfrage jetzt“ beim Öffnen der App (ab 0.4.2)

Sind Rückfragen offen, geht beim Öffnen der App ein Blatt mit der ältesten auf: voller Wortlaut, Kontext und
Empfehlung, darunter das Antwortfeld mit „Ja (Empfehlung)“, „Antworten“ und „Später“ (`A: QuestionPromptSheet.swift`,
Regeln in `C: Notify.swift` `QuestionPrompt`).

- „Öffnen“ heißt: Kaltstart oder zurück aus dem Hintergrund. Das Blatt kommt erst nach dem Verbinden und dem Abgleich
  mit dem PC, damit es nichts zeigt, was woanders schon beantwortet ist. Ohne Verbindung bleibt es zu.
- Es geht nie mitten in der Nutzung auf (eine neue Rückfrage kommt dann als Mitteilung und steht in „Dein Zug“), nie
  über der Face-ID-Sperre (dann nach dem Entsperren) und nicht, wenn die App über die Mitteilung geöffnet wurde.
- Nach einer Antwort rückt die nächste offene Rückfrage nach. Ist keine mehr offen, schließt sich das Blatt.
- „Später“ (auch Herunterwischen) merkt den Zeitstempel der neuesten offenen Rückfrage. Das Blatt bleibt zu, bis
  eine neuere dazukommt. Die Karten in „Dein Zug“ und die Zahl am Tab bleiben unverändert.

## Mikrofon und Büroklammer am Antwortfeld (ab 0.4.13)

Martin, 25.11.2026: Im Fenster zum Beantworten einer Rückfrage fehlten das Mikrofon und der Knopf zum Hochladen. Das
Tastaturdiktat erkennt schlechter als Relays eigene Spracherkennung, und eine Antwort soll auch ein Foto oder eine
Datei sein können. Beides steht jetzt am Antwortfeld, im Blatt „Rückfrage jetzt“ und in der Hinweis-Ansicht
(`A: DocIntake.swift` `AnswerComposer`, Kennungen `promptAttach`, `promptAnswer`, `promptMic` und `questionAttach`,
`questionAnswer`, `questionMic`).

- **Mikrofon (rechts am Feld):** dieselbe Erkennung wie im Jarvis-Chat (`VoiceIO`, auf dem iPhone, mit dem Vokabular
  des PCs). Es hört zu, bis eine Pause entsteht oder der Knopf noch einmal getippt wird. Das Gesprochene steht dann im
  Feld, hinter dem, was schon dort stand. Gesendet wird erst mit „Antworten“, der Text lässt sich vorher ändern.
- **Büroklammer (links am Feld):** dieselben Einträge wie im Jarvis-Chat (Fotos, Screenshots oder Videos aus der
  Mediathek, Kamera, Bild aus der Zwischenablage, Datei). Die Auswahl steht als Marken über dem Feld, Bilder mit
  Vorschau, jede mit einem Knopf zum Herausnehmen. „Antworten“ geht dann auch ohne Text.
- **Senden:** Die Anhänge gehen zuerst als Uploads an den PC (`upload_begin`, `upload_chunk`, `upload_end`, wie beim
  Jarvis-Upload). Die Pfade stehen am Ende der Antwort, alles in einer Zeile (`C: Notify.swift`
  `Rueckfrage.answerBody`): `Ja, siehe Foto. Anhang: /home/…/uploads/…/foto.jpg`, mehrere als
  `Anhänge: /pfad/a.jpg | /pfad/b.pdf`. Eine Zeile, weil das Skript `rueckfrage` die Antwort als eine Zeile in seine
  Notiz schreibt. Der Agent, der gefragt hat, liest die Datei unter dem Pfad. Am Gateway ist dafür nichts zu ändern.
- Scheitert das Hochladen, bleibt alles stehen und es steht „Anhang nicht hochgeladen: …“ da. Scheitert danach die
  Antwort, steht sie mit den Pfaden im Feld, ein zweiter Versuch lädt nichts doppelt hoch.
- „Ja (Empfehlung)“ nimmt angehängte Dateien mit. „Erledigt“ (schließt ohne Antwort) nicht.
- Die Karten in „Dein Zug“ haben weiter nur das Textfeld. „Ganz lesen“ auf der Karte öffnet die Hinweis-Ansicht mit
  Mikrofon und Büroklammer.

Die Annahme von Fotos und Dokumenten ist ein gemeinsamer Baustein für Jarvis-Chat und Antwortfeld (`DocIntake`,
`DocStrip`). Tests: `NotifyTests.testAnswerWithAttachmentsAndDictation`, UI-Test
`TabTests.test11_RueckfrageBlattMikrofonUndAnhang` (Mikrofon legt den Text ins Feld, „Antworten“ schickt ihn per
`inbox_put`). Das Hochladen selbst lässt sich im Simulator nicht prüfen (keine Dateiauswahl).

## Vorschlag für `~/.agents/bin/rueckfrage` (Stand 06.11.2026, inzwischen am PC umgesetzt)

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
- RelayCore: `NotifyTests.testResolveByTag`, `testReconcileWithDesktop`, `testClosedQuestionTexts`.
- RelayCore: `NotifyTests.testQuestionPromptOnOpen`. Simulator: `TabTests.test08_RueckfrageBlattSpaeter`,
  `test09_RueckfrageBlattJa` (App in den Hintergrund und wieder nach vorn).
- Simulator: `TabTests.test06_DeinZugRueckfrageErledigt`, `test07_RueckfrageAmPCBeantwortet` (Mock-Auslöser
  `trigger_rueckfrage_pc`, RPC `rueckfrage_status` im Mock).
- Simulator: `InfoTests.test20_AgentQuestion` (Mock-Auslöser `trigger_rueckfrage`, Antwort im Hinweis, `inbox_put`
  beim Mock angekommen).
- Von Hand am PC, sobald das Skript den Push kann: `~/relay/gateway/.venv/bin/notifyd phone notify --title
  "Rückfrage R1 · test" --text "Soll ich weitermachen?\nEmpfehlung: ja" --source test --tag rueckfrage:test:R1`,
  dann am iPhone antworten und `notifyd phone inbox --kind notification --app rueckfrage` prüfen.
