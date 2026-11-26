# Jarvis: Gesprächskontext zurücksetzen

Stand: 2026-11-24, Version 0.4.4. Backlog-Wunsch vom 23.11.2026: Der Gesprächskontext von Jarvis soll regelmäßig
zurückgesetzt werden, damit er nicht vollläuft. Wann und wie (Zeit, Größe, Knopf), war beim Bau zu klären.

## Was es heute schon gibt (Gateway, ohne Änderung)

Jarvis ist am PC ein eigener Claude-Lauf des Gateways (`gateway/src/notifyd/router.py`, Klasse `Router`). Sein
Gespräch wird schon heute von selbst neu begonnen:

- **Nach Zeit:** ein Gespräch je Tag. Der Tag beginnt um 4 Uhr (`DAY_STARTS_H = 4`), ein Gespräch nach Mitternacht
  gehört noch zum Abend davor.
- **Nach Größe:** Wird der Verlauf des Tages größer als 600 KB (`SESSION_MAX_BYTES = 600_000`), beginnt mit der
  nächsten Frage ein neues Gespräch.
- Dauerhaftes steht nicht im Gespräch, sondern in der Memory-Datei von Jarvis (`remember`, `read_memory`). Die
  laufenden Sitzungen bekommt er mit jeder Frage frisch mit.
- Ohne Frage beendet das Gateway den Jarvis-Prozess nach 30 Minuten (`overview.idle_stop_min`). Das spart
  Arbeitsspeicher, setzt das Gespräch aber nicht zurück (die nächste Frage setzt es fort).

„Chat löschen“ in der App löscht nur den Verlauf auf dem iPhone, nicht das Gespräch am PC.

## Was die App seit 0.4.4 zeigt

- Im Jarvis-Chat steht eine Trennlinie „Neues Gespräch. Jarvis kennt das Frühere nicht mehr.“ an jeder Stelle, an
  der am PC ein neuer Tag begonnen hat (4 Uhr). Liegt der letzte Zug an einem früheren Tag, steht am Ende „Die nächste
  Frage beginnt ein neues Gespräch.“ So ist sichtbar, worauf sich Jarvis noch beziehen kann.
- Den Wechsel nach Größe (600 KB) kann die App nicht sehen, dafür fehlt die Auskunft des Gateways (siehe unten).
- Vorbereitet: Meldet das Gateway den Füllstand, zeigt das Jarvis-Menü (oben rechts) „Gespräch am PC zu N % gefüllt“
  und den Knopf „Neues Gespräch beginnen“. Der Verlauf auf dem iPhone bleibt dabei stehen, an der Stelle erscheint
  die Trennlinie. Ohne die Auskunft des Gateways bleiben Füllstand und Knopf ausgeblendet (kein toter Knopf).

Technik: RelayCore `JarvisContext.swift` (Tagesgrenze, Trennstellen, Füllstand) mit `JarvisContextTests`, App
`JarvisView.swift` (Trennlinie, Menüabschnitt), `AppModel+Voice.swift` (`jarvisInfo`, `jarvisReset`).

## Wenn der Chief das Gespräch führt (seit 0.4.10)

Seit dem 25.11.2026 geht das Jarvis-Feld an den Chief, eine Agentensitzung am PC. Für ihn gelten Füllstand und „Neues
Gespräch beginnen“ nicht: Er beginnt täglich neu und dann, wenn sein Kontext voll wird. Dazu kommt die Ablösung auf
Zuruf:

- Im Jarvis-Menü steht der Abschnitt „Chief führt das Gespräch“ mit „Chief ablösen“. Nach der Nachfrage bittet das
  Gateway den Chief, seine Notizen zu schreiben und sich abzulösen. Ersetzt wird die Sitzung beim nächsten ruhigen
  Punkt, nie solange bei ihm Hintergrundarbeit läuft. Der Verlauf auf dem iPhone bleibt.
- Derselbe Weg per Sprache: „lös dich ab“ im Jarvis-Feld. Der Chief schreibt seine Notizen und ruft das Werkzeug
  `hand_over()` selbst.
- Vertrag: `jarvis_context` → `{"lead": "<Name>", "hand_over": true, "asked_at"?: <Zeit>}`, `jarvis_reset` →
  `{"lead": "<Name>", "asked": true|false}` (`false`: Es gibt gar keine Sitzung). Ohne `hand_over` in der Antwort
  zeigt die App den Menüpunkt nicht.
- Stand 26.11.2026: Die App-Seite ist fertig, der Gateway-Teil liegt als geprüfter Patch bereit und ist noch nicht
  eingespielt (`docs/nachtlog.md`, Nachtbau 26. November 2026, 08:30).

Technik: RelayCore `JarvisContext.lead`, `leadLabel`, `handOverNotice`, App `JarvisView.swift` (`handOver`),
`AppModel+Voice.swift` (`jarvisInfo`).

## Was im Gateway fehlt (nicht gebaut, `~/relay` blieb unberührt)

Zwei kleine RPCs in `daemon.py`, beide gegen `self.router_agent`:

1. `jarvis_context` (ohne Parameter) → `{"bytes": <Größe des Transkripts des laufenden Gesprächs>, "max_bytes":
   600000, "day": "JJJJ-MM-TT", "day_starts_h": 4}`. Die Größe steht in `Router._transcript(sid).stat().st_size`,
   ohne Transkript 0. Die App braucht `bytes` und `max_bytes`.
2. `jarvis_reset` (ohne Parameter) → `{}`: den Eintrag `router_session:<home>` im State auf eine neue Sitzungs-ID
   setzen (wie `Router._session` es bei neuem Tag tut), den laufenden Prozess schließen (`Router.close()` unter
   `self.lock`, nie während einer Antwort) und mit `prestart()` neu starten.

Dazu je eine Zeile in `PROTOCOL.md`. Läuft Jarvis Live (`_jarvis_live_url()`), führt Jarvis Live sein eigenes
Gespräch; dort sollten beide RPCs „unknown rpc“ oder einen leeren Füllstand liefern.

## Vorschlag an Martin

- **Zeit:** bei 4 Uhr bleiben. Ein Gespräch je Tag passt zum Tageslauf, und Jarvis merkt sich Dauerhaftes ohnehin
  in seiner Memory-Datei.
- **Größe:** 600 KB beibehalten. Das ist weit unter der Grenze, ab der das Modell selbst verdichten müsste, und hält
  die Antworten schnell.
- **Knopf:** „Neues Gespräch beginnen“ im Jarvis-Menü, sobald das Gateway die beiden RPCs hat (App-Seite ist fertig).
  Sinnvoll, wenn Jarvis sich an einem alten Thema festbeißt.
- **Offen für Martin:** Soll zusätzlich nach einer langen Pause (zum Beispiel 3 Stunden ohne Frage) ein neues Gespräch
  beginnen? Das wäre eine Zeile im Gateway, kostet aber den Bezug auf den Vormittag.
