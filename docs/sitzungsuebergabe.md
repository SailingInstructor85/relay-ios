# Sitzungsübergabe Handy und PC

Stand 2026-11-06 (Nachtarbeit, ohne vorheriges Grill-me). Zweig `uebergabe` in `relay-ios` (diese Datei, App) und in `relay` (Gateway, aufgesetzt auf `lokal-clear-beendet`). Lokal, nicht gepusht.

## Ziel

Am Handy in Relay sagen: "Diese Sitzung übernehme ich jetzt." Am PC ist sichtbar, dass das Handy sie hält. Zurück am Rechner: im selben Terminalfenster zurückholen und weiterarbeiten.

## Machbarkeit: ja, über tmux

Alle Agentensitzungen laufen in tmux. Das Handy liest per `capture-pane` und schreibt per `send-keys` und `paste-buffer`. Am PC hängt ein `tmux attach`-Client am selben Pane. Das trägt:

| Baustein | Ergebnis (mit tmux 3.8 an einem privaten Socket geprüft) |
|---|---|
| PC-Client schreibgeschützt setzen (`switch-client -c <client> -r`) | geht. Tasten des PC-Clients werden verworfen, der Agent bekommt nichts. |
| Gateway tippt weiter ins Pane | geht nur mit Umweg. `send-keys` scheitert mit "client is read-only", sobald der beste Client der Sitzung schreibgeschützt ist (das Gateway ist kein Client, tmux nimmt aber den angehängten). `send-keys -c ""` (leerer Client) umgeht das. `paste-buffer` ging schon. `tmux.py` wiederholt jetzt bei dieser Meldung mit `-c ""`. |
| Befehle am schreibgeschützten Client | `run-shell`, `if-shell`, `set-option`, `source-file` werden dort abgelehnt. Erlaubt sind `detach-client` (auch mit `-E <Befehl>`) und `switch-client -r`. |
| Zurückholen im selben Fenster | `Strg-b H` ist an `detach-client -E "python -m notifyd.handover back"` gebunden. Das löst den Client, führt den Befehl im selben Terminal aus (Zustand zurücksetzen) und hängt mit `tmux attach` wieder an. Kurzes Flackern, danach normal bedienbar. |
| Sichtbare Anzeige am PC | Sitzungs-Statuszeile wird rot mit "AM HANDY ÜBERNOMMEN. Hier weiterarbeiten: Strg-b, dann H". Dazu eine `display-message` an jeden PC-Client. |
| Neuer PC-Client während der Übernahme | Hook `client-attached` an der Sitzung sperrt ihn ebenfalls. |
| Phone-Terminals (`phone-*`, gruppierte Sitzungen) | werden nie gesperrt. |

### Was nicht geht oder anders ist

- **Der Satz "Übernimm wieder hier" lässt sich am PC nicht als Text erkennen.** Ein schreibgeschützter Client verwirft alle Eingaben, tmux hat keinen Zugriff auf getippten Text. Stattdessen: `Strg-b H` (oder `relay-hier` in einem zweiten Terminal). Wäre der Client nicht gesperrt, würde der Satz als Prompt beim Agenten landen. Ein `UserPromptSubmit`-Hook in Claude Code könnte den Satz abfangen, bräuchte aber Änderungen an `settings.json` (nicht von mir angefasst) und kann Handy und PC nicht unterscheiden. Als Variante unten vermerkt, nicht gebaut.
- **Sitzungen außerhalb von tmux** (Terminal ohne tmux, `bg`-Läufe ohne Pane) lassen sich nicht übergeben. Das Handy sieht sie nur lesend (Transkript), wie bisher. Die App zeigt den Übernehmen-Knopf nur bei `liveTmux`.
- **`claude --resume`** wäre ein zweiter Claude-Prozess auf derselben Transkriptdatei. Beide schreiben, der Verlauf verzweigt, und der alte Prozess läuft weiter. Für die Übergabe ungeeignet. Es bleibt der Weg "geschlossene Sitzung wieder öffnen" (`reopen`), der schon existiert.
- **`claude remote-control`** (Claude-App steuert eine lokale Sitzung über Anthropic-Server) ist ein eigener Kanal der Claude-App und kein Teil von Relay. Er ändert an diesem Entwurf nichts und wurde nicht angefasst. Die tmux-Sitzung `claude-rc` ist unberührt.

## Entwurf

Zustand je Agentensitzung als tmux-Option `@relay_holder` (überlebt Gateway-Neustarts, am PC ohne Dienst lesbar):

| Halter | Bedeutung | PC | Handy |
|---|---|---|---|
| `""` (offen, Standard) | wie bisher | tippt | tippt |
| `phone` | Handy hält | schreibgeschützt, rote Statuszeile | tippt |
| `desk` | PC hat sie ausdrücklich zurückgeholt | tippt | Gateway lehnt `send` ab ("session is held by the PC") |

Der Standard bleibt "offen", damit sich für alle Sitzungen ohne Übergabe nichts ändert. `desk` entsteht nur durch `Strg-b H`, `relay-hier` oder `handover to: desk`.

Weitere tmux-Optionen: `@relay_holder_since` (Zeitpunkt), `@relay_ro_clients` (welche PC-Clients wir gesperrt haben: nur diese gibt die Rückgabe frei, ein von Martin selbst mit `attach -r` angehängter Client bleibt schreibgeschützt), `@relay_prev_*` (vorherige lokale Werte der Statuszeile, werden wiederhergestellt).

### Protokolländerungen (PROTOCOL.md, Abschnitt "Session handover")

- Neu `handover {key|target, to?: "phone"|"desk"|"open"}` -> `{holder, since, pc_clients, session}`. Ohne `to` nur der Zustand.
- `screen` liefert zusätzlich `holder`. `list_sessions`-Zeilen tragen `holder`, wenn gesetzt (fehlt: offen). Ältere Gateways liefern kein `holder`, die App behandelt das als offen.
- `send` (mit `key` oder `target`) wird abgelehnt, solange `holder == "desk"`.
- Gateway-CLI: `notifyd handover <key|tmux:name> [--to phone|desk|open]`, läuft ohne den Dienst. Neues Skript `relay-hier` (Eintrag in `pyproject.toml`, nach `uv sync` oder Neuinstallation vorhanden). `python -m notifyd.handover back` geht ohne Installation.

## Bedienung

**iPhone.** Chat öffnen, Menü (drei Punkte), "Sitzung übernehmen". Oder die orange Leiste über dem Eingabefeld (erscheint, sobald jemand die Sitzung hält). Hält das Handy sie, steht dort "Am Handy. Am PC zurückholen mit Strg-b, dann H." mit Knopf "An PC zurückgeben". Hält der PC sie ausdrücklich, ist Senden gesperrt, bis man übernimmt. In der Sitzungsliste ein Tag "Am Handy" oder "Am PC", im Live-Bildschirm eine Zeile mit demselben Hinweis.

**PC.** Statuszeile rot. Zurückholen: `Strg-b`, dann `H` (Standard-Präfix von tmux, bei geändertem Präfix das eigene). Das Fenster hängt sich neu an, die Statuszeile ist wieder normal, die Sitzung steht auf `desk` (das Handy muss erst wieder übernehmen, bevor es tippen darf). Alternativ in einem zweiten Terminal `relay-hier [sitzung]`. Dort, wo man schon per Handy-Übergabe gesperrt ist, geht das auch ohne Gateway.

## Grenzen und Risiken

- `Strg-b H` bindet die Taste `H` im tmux-Server global (Präfix-Tabelle). Wer sie belegt hat, verliert die Belegung, sobald eine Übergabe läuft. `H` hat in tmux keine Standardbelegung.
- Das Zurückholen setzt `desk`. Wer danach weggeht und das Handy nutzen will, muss einmal "Übernehmen" tippen. Gewollt (klare Besitzverhältnisse), aber eine Reibung.
- Die Statuszeile ist sitzungsweit. Hängt Martin mit mehreren Terminals an derselben Sitzung, sehen alle den Banner.
- `back` startet Python (importiert das Paket, etwa 0,3 s). Das ist das Flackern.
- Der Hook `client-attached` und die Taste brauchen den Python-Pfad der Venv, der beim Übernehmen eingetragen wird. Nach einem Venv-Umzug muss einmal neu übernommen werden.
- Zustand geht mit dem tmux-Server verloren (Neustart des Rechners). Das ist gewollt: danach ist alles offen.
- Befehle, die direkt am Pane vorbei zum Agenten gehen (Hooks, andere Skripte mit `tmux send-keys`) werden nicht gesperrt. Nur die Menschen-Eingabe über Clients und die `send`-RPC des Gateways.
- Die App sperrt nur die eigene Eingabe. Die Outbox kann eine vor der Sperre eingereihte Nachricht noch versuchen und bekommt dann die Gateway-Meldung.

## Teststand

- Gateway (Worktree `~/relay-wt-uebergabe`, Live-venv nur zum Ausführen mit `PYTHONPATH`): Basis 1010 bestanden, 13 übersprungen. Nach der Änderung 1018 bestanden, 13 übersprungen (8 neue Tests in `tests/test_handover.py` mit echten tmux-Clients im pty: Sperre, Banner, Rückgabe, später angehängter Client, `Strg-b H` mit erneutem Anhängen, selbst gesetzter Schreibschutz bleibt, Phone-Terminals bleiben frei, RPC mit `send`-Sperre).
- App: **nicht kompiliert und nicht getestet.** Auf diesem Rechner gibt es keinen Swift-Compiler. Der Swift-Code (`Handover.swift` in RelayCore, `HandoverTests`, Änderungen in `AppModel.swift`, `ChatView.swift`, `ScreenView.swift`, `SessionsView.swift`) wurde nur gegengelesen. Der CI-Lauf (core-tests, ipa) ist die erste echte Prüfung.
- Mock-Gateway (`testing/mock_gateway.py`) kennt `handover`, `holder` in `screen` und `list_sessions` und die Sperre bei `send`. Keine neuen UI-Tests geschrieben (ohne Simulator nicht prüfbar).
- Nicht gegen Martins echte tmux-Sitzungen und nicht gegen den Live-Dienst getestet, nur an privaten Sockets.

## Getroffene Annahmen

1. Der Standard bleibt "offen"; Sperre des Handys nur nach ausdrücklichem Zurückholen am PC.
2. "Im selben Terminalfenster sagen" heißt: eine Taste im selben Fenster ist akzeptabel, weil ein getippter Satz technisch nicht abfangbar ist.
3. Schreibschutz (Tasten verwerfen) ist besser als nur ein Hinweis, weil sonst beide gleichzeitig tippen (der heutige Zustand).
4. Nur Sitzungen in einer Agenten-tmux-Sitzung (`@agent_alias`).
5. `H` als Taste, Präfix unverändert Strg-b.
6. Die Statuszeile darf pro Sitzung rot werden.
7. Das Gateway bekommt die Funktion ohne neue Abhängigkeiten, ohne Datenbank, ohne Konfiguration.

## Fragen an Martin für morgen

1. Soll nach "Am PC zurückholen" das Handy gesperrt sein (jetzt so), oder reicht der Hinweis und beide dürfen weiter tippen?
2. Passt `Strg-b H`? Oder lieber eine Taste ohne Präfix wie `F12` (würde in jedem Client gelten) oder ein anderer Buchstabe?
3. Reicht eine Taste statt des gesprochenen oder getippten Satzes? Wenn der Satz wichtig ist: Variante mit Claude-Code-Hook (`UserPromptSubmit`) möglich, braucht eine Änderung an `settings.json` von dir und unterscheidet nicht zwischen PC und Handy.
4. ~~Automatisch übernehmen bei Abwesenheit?~~ Entschieden (Martin, 2026-11-05): nein. Übergabe nur auf ausdrücklichen Wunsch, kein Automatismus.
5. Soll die rote Statuszeile bleiben oder ein ruhigerer Hinweis (nur Meldung beim Tippen)?
6. Livebetrieb: Die Funktion läuft erst, wenn notifyd aus dem Zweig `uebergabe` (oder nach Merge) startet. Soll ich den Zweig auf `lokal-clear-beendet` zurückführen, wenn du zufrieden bist, und wann den Dienst neu starten?
7. `relay-hier` als Skript in der Venv ist nach einem Neu-Sync da. Soll es zusätzlich nach `~/.local/bin` verlinkt werden?

## Stand 2026-11-06 (Nachtbau 18:30)

- App: Zweig `uebergabe` ist in `nachtbau/2026-11-06-1830` zusammengeführt (`d6e4416`). Gateway: `uebergabe` ist auf `lokal-clear-beendet` zurückgeführt (`8908858`), Tests grün. Der Dienst läuft erst nach einem Neustart von notifyd mit dem neuen Stand (Rückfrage an Martin).
- Neu: Vor dem Senden in eine Sitzung, die ein Terminal am PC gerade zeigt (`pc_attached` in `list_sessions`, aus `tmux list-clients` ohne `phone-*`) oder die der PC hält, fragt die App „Sitzung vom PC übernehmen?“ mit „Übernehmen und senden“, „Nur senden“ (nicht bei Halter `desk`) und „Abbrechen“. Nichts wird automatisch übernommen. „Nur senden“ gilt für diese Sitzung bis zum Neustart der App.
- Sitzungen außerhalb von tmux bleiben von der Übergabe ausgeschlossen. Dafür gibt es jetzt `send` mit `move` („Am PC beenden und hier fortsetzen“, siehe feature-parity C21): nach Martins Ja beendet das Gateway die Sitzung am PC und setzt sie in tmux fort. Danach greift die Übergabe wie bei jeder tmux-Sitzung.
- Antworten auf die offenen Fragen 5 und 7 (Empfehlung des Nachtbaus): 5. Die rote Statuszeile bleibt, solange das Handy hält; sie ist der einzige Hinweis, der am PC ohne Tippen sichtbar ist, und ein Tippen in einen schreibgeschützten Client zeigt sonst nichts an. 7. `relay-hier` nicht nach `~/.local/bin` verlinken; am PC reicht `Strg-b H`, und `python -m notifyd.handover back` läuft ohne Installation. Ein Link wäre eine zweite Stelle, die nach einem Venv-Umzug kaputtgeht.
