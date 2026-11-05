# Auftrag: Shell-Sitzung vom iPhone und Diktat-Abbruch

Stand 2026-11-05, geschrieben von einer anderen Claude-Sitzung (Analyse, nichts geändert).
Freigabe der Punkte unten durch Martin im Gespräch vom 2026-11-05.

## 1. Shell-Sitzung (Feature)

**Ziel:** Martin muss Befehle, die nur er ausführen darf (vor allem `sudo`), vom iPhone aus
starten können. `! sudo …` in einer Claude-Sitzung funktioniert nicht, Claude verweist dann auf
ein echtes Terminal.

**Befund:**
- `ScreenView.swift` (Live-Bildschirm mit Tastenleiste und Eingabe) reicht als Terminal-Ansicht.
- Das Gateway nimmt bei `screen`/`send` mit `target: tmux:<name>` nur Agent-Sitzungen an
  (`~/relay/gateway/src/notifyd/ssh_entry.py`, `resolve_target`, prüft `tmux.list_agent_sessions()`,
  also `@agent_alias`).
- `launch` (`launcher.py`) startet nur Agenten-Konten, keine Shell.
- `attach` (PTY) gibt es im Gateway, die App nutzt es nicht.

**Bauen:**
1. Gateway: Sitzungsart „Shell“: eine Bash im Home in einer markierten tmux-Sitzung (eigener
   Marker, z. B. `@agent_tool=shell`), die `screen`/`send` zulassen und die in der Sitzungsliste
   erscheint. Rechteprüfung der Agenten bleibt unberührt (`auto_trust: false`,
   `skip_permissions: false`, nie `setup accounts`).
2. App: Knopf „Neues Terminal“; eine Shell-Sitzung öffnet direkt den Live-Bildschirm statt des Chats.
3. App: In Antworten von Claude Befehle erkennen (Codeblöcke und Inline-Code mit `sudo …`
   oder `! …`, das `!` abschneiden). Daneben zwei Aktionen:
   - „Im Terminal einsetzen“: öffnet bzw. erstellt die Shell-Sitzung und setzt den Befehl
     **ohne Enter** in die Zeile. Martin prüft und tippt selbst ⏎, dann das sudo-Passwort.
   - „Kopieren“: Befehl in die Zwischenablage.
4. Prüfen, dass eingetippter Text (Passwort!) nicht in Gateway- oder App-Logs landet
   (`send`, `AppLog.swift`, Outbox, Journal). Falls doch: für Shell-Sitzungen nicht protokollieren.

**Sicherheit (Martin weiß Bescheid):** Das ist eine echte Ausweitung, das iPhone kann dann
beliebige Befehle als martin ausführen. Zugang bleibt Schlüssel-Login, nur WLAN/Tailscale.

## 2. Bug: Diktat bricht bei längeren Aufnahmen ab

**Erledigt am 2026-11-05 (lokal committet, noch nicht gebaut):** Pause 3 s, kein Gesamtlimit,
Erkenner startet bei Ablauf oder Fehler neu und hängt Text an. Gilt für Chat-Diktat und Jarvis.

**Meldung Martin:** Bei längerer Sprachaufnahme schaltet sich das Mikrofon manchmal einfach ab.

**Vermutliche Ursachen in `App/Sources/Voice.swift` (`listen`, Watchdog ab ca. Zeile 87):**
- Ende nach 1,6 s Pause, sobald etwas erkannt wurde. Beim Diktieren mit Denkpausen viel zu kurz.
- Hartes Ende nach 45 s Gesamtdauer.
- `final` wird auch bei jedem `error` gesetzt (`recognize`), jeder Erkennerfehler beendet die Aufnahme.
- Zusätzlich begrenzt Apple eine einzelne Erkennungsaufgabe (etwa 1 Minute).

Diese Grenzen passen zu Jarvis (kurze Kommandos), nicht zum Diktat im Chat (`ChatView.swift`, ca. Zeile 197).

**Vorschlag:**
- Getrennte Einstellungen für Jarvis und Chat-Diktat. Chat-Diktat endet nur per Knopf
  (oder nach langer Stille, z. B. 30 s).
- Für lange Diktate die Erkennungsaufgabe bei Ablauf oder Fehler nahtlos neu starten und den
  bisherigen Text anhängen, statt die Aufnahme zu beenden.
- Fehler protokollieren, damit man sieht, welcher Grund das Ende auslöste.

Log und Changelog in der Vault (`02 Projekte/Relay/`) wie üblich mitführen.
