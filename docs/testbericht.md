# Testbericht Simulator (Nacht 4./5. November 2026)

Ziel: jede Funktion, die in einem Simulator laufen kann, wird ausgeführt, fotografiert und auf Fehler geprüft. Das Ergebnis steht hier. Alle Daten im Test sind erfunden (kein echter Nutzer, kein echter Desktop).

## Aufbau

- **Mock-Gateway** `testing/mock_gateway.py` (Python 3, nur Standardbibliothek). Spricht das `serve`-Protokoll aus `PROTOCOL.md`: `hello`, Wiedergabe mit `replay`, `hello_ok` (Sitzungen, Konten, Konfiguration), RPCs mit `rpc_result` und `rpc_progress`, Live-Ereignisse. Unbekannte RPCs antworten wie das echte Gateway mit `unknown rpc`. Zustand und Protokoll liegen in `/tmp/relaymock` (`state.json`, `rpc-all.jsonl`, `mock.log`), Steuerdateien in `control/` (`offline`, `kick`, `trigger_<name>`).
- Datenbasis: zwölf Sitzungen in allen Zuständen (arbeitet mit laufenden Aufgaben, bereit, wartet mit AskUserQuestion, `asks: true` bei Codex, beendet, ruhend, geschlossen, Hintergrundlauf, Menükarte, Freigabedialog, Panel, Formular), zwei Konten (Claude c1, Codex x1), Verlauf mit 130 Nachrichten (Markdown, Code, Tabelle, Links, Pfade, Werkzeugzeilen), Dateien (Markdown, Python, PNG, PDF, Text), Nutzung mit dem Fehler "usage helper unavailable" bei Claude und Fenstern samt Prognose bei Codex, RAM, Cloud, Digest, Tokens, Profil, Stimmvokabular, Upload.
- **SSH auf dem CI-Läufer**: `testing/ci_sshd.sh` startet einen eigenen `sshd` auf 127.0.0.1:2222 mit eingeschränktem Testschlüssel (`restrict,pty,command="python3 .../mock_gateway.py"`). Der öffentliche Schlüssel wird aus dem festen Test-Seed berechnet (`testing/ci_keygen.py`, RFC 8032). Vor den UI-Tests prüft ein gewöhnlicher `ssh`-Aufruf, dass `hello_ok` ankommt.
- **Testmodus in der App** (`App/Sources/UITestMode.swift`): nur mit dem Startargument `-relayUITest`. Setzt Einstellungen und Dateien zurück, übernimmt Host, Port, Benutzer und den Seed aus der Startumgebung und schaltet die Face-ID-Sperre ab.
- **XCUITest-Ziel `RelayUITests`** (`App/UITests`): 60 Tests in sieben Klassen. Jeder Schritt macht einen Screenshot (`XCTAttachment`, `keepAlways`). Prüfungen gegen den Mock lesen `rpc-all.jsonl` (kam die Nachricht an?).
- **CI-Job `simulator`** (`.github/workflows/ios.yml`): Simulator wählen (neuestes iPhone Pro), sshd und Mock, `build-for-testing`, `test-without-building`, Export der Anhänge aus der `.xcresult`, Upload von Screenshots, Zusammenfassung, Logs und der `.xcresult` (immer, auch bei Fehlern). `testing/only.txt` wählt bei Bedarf einzelne Tests.
- Simulator im letzten vollen Lauf: iPhone Pro (neuestes), iOS 26, Sprache Deutsch.

## Was getestet wurde

Vollständiger Lauf vor den letzten kleinen Korrekturen: CI-Lauf 41991991560, **60 Tests, 0 Fehler**. Die Korrekturen (Dateiansicht, Beschriftungen) prüfte Lauf 42000379796 (ChatTests und ScreenTests, 18 Tests, 0 Fehler). Der Abschlusslauf mit allen Tests steht am Ende dieses Berichts.

| Klasse | Tests | Inhalt |
|---|---|---|
| SetupTests | 2 | Ersteinrichtung (Schlüssel, Befehl kopieren, Host, Port, Benutzer, Verbinden), Host-Schlüssel wird gepinnt, Trennen und Wiederverbinden |
| ListTests | 10 | Abschnitte, Triage-Streifen, Suche, Anheften, Stumm, Kontextmenü, Schließen mit Rückgängig, Bestätigung bei arbeitender Sitzung, Umbenennen, Laufend und Zuletzt, Hintergrundläufe, Wieder öffnen, Live-Ereignisse (fertig, neue Frage, beendet, Desktop schläft), Offline-Liste |
| ChatTests | 11 | Verlauf, Scrollen und Nachladen, Nachrichtenmenü, Text auswählen, Links, Dateiansicht (Markdown, Code, Bild mit Zoom, PDF), Werkzeugzeile mit Pfad, laufende Aufgaben, Suche im Verlauf, App-Suche über Gespräche, Zusammenfassung, Anheften, Schließen |
| ComposeTests | 8 | Senden (Mock bestätigt), Antwort per `transcript_append`, Slash-Chips, Senden an arbeitende Sitzung, Outbox ohne Verbindung und Nachsenden, Anhang-Menü, Dateiauswahl, Modellmenü |
| ScreenTests | 7 | Fragenformular (mehrere Fragen, Mehrfachauswahl, Antworten senden, Ablehnen), Menükarte (Modell), Freigabedialog, Panel, Formularkarte, Live-Bildschirm mit Tastenleiste und Textzeile |
| NewSessionTests | 3 | Konto wählen, Ordnersuche, Durchsuchen, Ordner anlegen (`mkdir`), Starten (`launch`) |
| InfoTests | 19 | Nutzung (Fehlertext des Pool-Helfers, Codex-Fenster, Prognose), RAM-Monitor, Was war los, Token-Verbrauch, Desktop ausschalten (Testlauf, zweistufig), Cloud-Zeilen, Hinweise, Freigabe-Streifen und Sheet (`send_result`), Jarvis mit gestreamter Antwort, Erkennung korrigieren, Einstellungen (alle Abschnitte), Mitteilungen und Ruhezeiten, Sprache und Stimme, Profil-Editor, Jarvis-Agent, Sitzungs-Einstellungen, Host-Schlüssel vergessen, Standortanfrage |

## Screenshots

Kuratiert unter `docs/screenshots/` (39 Bilder, verkleinert auf 600 px Breite): Einrichtung, Liste, Suche, Kontextmenü, Rückgängig, Zuletzt, Live-Ereignis, Offline, Chat mit Markdown und Tabelle, Nachrichtenmenü, Dateiansichten, laufende Aufgaben, Suche im Chat, Zusammenfassung, Senden, Slash-Chips, Outbox, Fragenformular, Menükarte, Freigabedialog, Panel, Live-Bildschirm, neue Sitzung, Nutzung, RAM, Was war los, Tokens, Desktop ausschalten, Hinweis, Freigabe, Jarvis, Vokabular, Ruhezeiten, Sprache und Stimme, Profil. Alle rund 150 Bilder des Laufs liegen als CI-Artefakt `simulator-results` (30 Tage) vor.

## Gefundene und behobene Fehler

1. **Tote Verbindung als "Verbunden"** (`66d865d`): Ereignisse einer schon ersetzten oder geschlossenen Verbindung konnten den Zustand auf "Verbunden" setzen, obwohl die aktuelle Verbindung noch aufbaute. Folge: Banner "Nicht verbunden: Verbunden", leere Chats, scheiternde Suche, leeres "Zuletzt". Ursache war auch, dass der Wechsel in den Vordergrund eine gerade aufbauende Verbindung abbrach und ein zweiter Aufbau startete (der Mock sah zwei `serve` im selben Moment). Behoben: Rückrufe zählen nur noch für die aktuelle Verbindung, der Vordergrundwechsel lässt eine aufbauende Verbindung in Ruhe. Wichtigster Fund der Nacht, hätte auf dem Gerät bei jedem Start auftreten können.
2. **Einrichtung: Befehl kopieren und Teilen in einer Zeile** (`fef9ca3`): Ein Tipp löste beide Knöpfe aus (das Teilen-Blatt öffnete sich beim Kopieren). Behoben mit `.buttonStyle(.borderless)`.
3. **Übersicht ohne sichtbaren Titel** (`a129571`): der große Titel "Relay" war nicht zu sehen, oben blieb eine leere Fläche. Titel jetzt inline.
4. **Chat-Titel** (`66d865d`): Untertitel und "Stand" liefen unter die Symbolleiste. Breite begrenzt, Untertitel kürzt am Anfang.
5. **Profil-Editor ohne Beschriftung** (`4bb93b7`): ausgefüllte Felder zeigten nur den Wert ("7", "12345"). Jetzt steht die Beschriftung darüber.
6. **Texte** (`4bb93b7`): "1 Sitzungen arbeiten gerade", "1 Korrekturen", "Sek.." (doppelter Punkt in der Cloud-Fußzeile), englische Zustandswörter im RAM-Monitor (`needs_input`, `idle`, `busy`).
7. **Dateiansicht für Text** (`18288ba`): kein Rand, Text mittig und links abgeschnitten. Jetzt oben links mit Rand.
8. **Fehlende Beschriftungen** (`6ca34d6`, `a700ea2`): Schriftgrößen-Knöpfe im Live-Bildschirm, Büroklammer und Jarvis-Senden-Knopf hatten keine Beschriftung (VoiceOver). Zusätzlich trimmt der Jarvis-Senden-Knopf jetzt Zeilenumbrüche.

Ergebnis: 8 Fehler behoben (1 schwer, 3 mittel, 4 klein). Fehler in den Tests selbst (Scrollen in lazy Listen, Tastatur verdeckt Felder, falsche Namen) sind nicht mitgezählt.

## Beobachtungen ohne Änderung

- `send` an eine arbeitende Sitzung geht über das tmux-Ziel und umgeht die Busy-Sperre (wie im echten Gateway). "Trotzdem senden" erscheint deshalb nur ohne tmux und war im Simulator nicht auslösbar.
- Pfade im Fließtext einer Nachricht lassen sich in XCUITest nicht gezielt antippen (Links in einem `Text`). Getestet ist der Pfad über die Werkzeugzeile ("Read · README.md").
- Beim Bestätigungsdialog zum Schließen einer arbeitenden Sitzung zeigt iOS 26 als Popover keinen "Abbrechen"-Knopf (Systemverhalten).
- Die XCUITest-Protokolle zeigen nur "Automation type mismatch" (SwiftUI-Barrierefreiheit, harmlos) und CoreHaptics-Meldungen des Simulators. Keine Abstürze, keine Absturzberichte.
- Einige Prüfungen sind bewusst weich (landen als Notiz): "Weitere Angaben" und "Cloud-Guthaben" liegen unterhalb des ersten Bildschirms, die Konto-Pille im Triage-Streifen erscheint erst nach dem ersten `usage`.

## Nicht im Simulator testbar

- Echte Mitteilungen bei geschlossener App (Push gibt es ohnehin nicht, nur Hintergrundabruf) und das Timing von Background Refresh.
- Face ID und Sperre beim Hintergrund (im Testmodus abgeschaltet).
- Spracherkennung, Mikrofon, Vorlesen mit echten Stimmen, Kopfhörer-Erkennung, Gesprächsmodus.
- Siri, Kurzbefehle, Aktionstaste, "In Relay öffnen" aus anderen Apps, Share-Sheet fremder Apps.
- Kamera, Fotoauswahl (Dialoge öffnen, Inhalt nicht prüfbar), Standortfreigabe (Anfrage kommt, Berechtigungsdialog nicht ausgewertet).
- WireGuard und echtes Netz (Simulator nutzt Loopback), Schlafen des Desktops, Weckversuche über Zeit (alle 5 Minuten).
- Echtes Ausschalten (der Testlauf ist an, der Mock ignoriert `power_off`).

## Restrisiken

- Der Mock bildet das Protokoll nach `PROTOCOL.md` nach. Abweichungen im echten Gateway (zum Beispiel Felder von `digest`, `session_tokens`, `running`) fallen erst am echten Desktop auf.
- Der Testlauf dauert rund 50 Minuten (60 Tests, jeder startet die App neu). Für schnelle Läufe gibt es `testing/only.txt`.
- Layout wurde nur auf einem iPhone Pro (iOS 26) gesehen. Kleine Geräte, Querformat, Dynamic Type groß und Dunkelmodus sind nicht abgedeckt.
- `-relayUITest` ist in jedem Build vorhanden. Es wirkt nur mit dem Startargument (nie ohne), löscht dann aber App-Daten. Ein Nutzer kann das nicht versehentlich auslösen.
- Der feste Test-Seed steht im Quelltext (erfunden, nur für CI, der Schlüssel gilt nur für den eigenen sshd im Lauf).

## Abschlusslauf und Stabilität

Der Lauf 42005893092 (alle 60 Tests) hatte im ersten Versuch einen Fehler in `ComposeTests.test04_OutboxWhenOffline` (UI-Abfrage nach 30 Sekunden Zeitüberschreitung) und im zweiten Versuch einen in `ListTests.test08_ReopenDormant` (Liste nach 30 Sekunden noch nicht da, laut Mock-Log war die Verbindung aber da). Beide Tests liefen in den Läufen davor und danach fehlerfrei, und beide Fehler traten erst nach rund 55 Minuten Laufzeit auf (der Simulator wird gegen Ende träge, "kAXErrorServerNotFound"). Gegenmaßnahme: Warten auf die Liste auf 60 Sekunden verlängert und `xcodebuild` wiederholt fehlgeschlagene Tests einmal (`-retry-tests-on-failure -test-iterations 2`). Der Abschlusslauf steht in `docs/nachtlog.md`.
