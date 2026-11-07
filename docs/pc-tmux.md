# Am PC in tmux arbeiten: Handy und PC in derselben Sitzung

Stand 7. November 2026 (Version 0.3.7). Ergebnis des Nachtbaus zu den Backlog-Einträgen „Eingaben erscheinen nicht
mehr auf beiden Geräten“, „Kein ‚Am PC beenden?‘ mehr“ und „Anzeige, ob die Sitzung gerade auch am PC offen ist“.

## Befund

Das Gateway kann nur in Sitzungen tippen, die in einer **Agenten-tmux-Sitzung** laufen (tmux-Sitzung mit den Optionen
`@agent_alias` und `@agent_tool`, Name wie `c1-<ordner>-xxxx`). So startet die App jede Sitzung („Neue Sitzung“,
„Wieder öffnen“). Was am PC als nacktes `claude` in einem Konsole-Fenster gestartet wird, läuft **ohne tmux**: dort
liest das Gateway das Transkript mit (PC → Handy geht), aber eintippen kann es nichts (Handy → PC geht nicht).

Nachgestellt am 7. November mit `testing/gateway_beide_richtungen.py` gegen den Gateway-Code `a3218d9` (der Stand
nach der Entfernung der Übergabe):

| Fall | Handy → PC | PC → Handy |
|---|---|---|
| Sitzung in Agenten-tmux-Sitzung | Text kommt an, Antwort kommt | am PC Getipptes erreicht die Watch-Schleife der App |
| Nacktes `claude` im Terminal (pty) | abgelehnt („outside tmux“) | Text und Antwort im Transkript |

Der Code der Übergabe-Entfernung hat also nichts kaputt gemacht. Der Unterschied zu „gestern ging es“: Am 6. November
liefen Martins Sitzungen in den tmux-Sitzungen `c1-martin-*` aus der App, am 7. November als nacktes `claude` in
Konsole-Fenstern (`pts/34`, `pts/35`, `pts/36`). In solchen Sitzungen bleibt die Nachricht vom Handy im Postausgang,
und bis 0.3.6 fragte die App von selbst „Am PC beenden und hier fortsetzen?“.

## Was die App seit 0.3.7 tut

- Keine Rückfrage mehr von selbst. Die Nachricht bleibt als graue Blase im Postausgang mit dem Grund „Nicht gesendet:
  die Sitzung ist am PC in einem Terminal ohne tmux offen“. Über der Eingabe steht der Hinweis „Am PC in einem
  Terminal ohne tmux offen: vom Handy nur mitlesen. Nachrichten warten im Postausgang.“
- Der Umzug in tmux gibt es weiterhin, aber nur auf ausdrückliche Wahl: Knopf „Am PC beenden und hier fortsetzen…“
  in der Postausgangszeile, danach eine Bestätigung „Ja, am PC beenden und hier fortsetzen“. Ohne beides passiert am
  PC nichts.
- Symbol „Am PC offen“ (Monitor) im Chat-Kopf und in der Sitzungsliste, sobald ein Terminal am PC die Sitzung zeigt
  (Gateway `pc_attached`, Live-Ereignis `pc_attached` alle 2 Sekunden geprüft). Eine Sitzung ohne tmux ist am PC
  offen, solange sie lebt. Nur Anzeige, keine Sperre, keine Rückfrage.

## Vorschlag: `claude` am PC immer in tmux starten

Der Launcher des Gateways legt genau die tmux-Sitzung an, die das Gateway erkennt, und hängt das Terminal daran
(`agent-run`, liegt im Venv des Gateways). Als Funktion in `~/.bashrc` (nur ein Vorschlag, nicht vom Nachtbau
eingetragen):

```bash
# Relay: claude am PC in einer Agenten-tmux-Sitzung starten, damit Handy und PC in dieselbe Sitzung tippen.
# Nur interaktiv, nicht in tmux, nicht für Unterbefehle und -p/--print.
claude() {
    local a
    for a in "$@"; do
        case "$a" in
            -p|--print|-v|--version|-h|--help|update|doctor|mcp|auth|login|logout|setup-token|install|migrate-installer)
                command claude "$@"; return;;
        esac
    done
    if [ -z "$TMUX" ] && [ -t 0 ] && [ -t 1 ]; then
        ~/relay/gateway/.venv/bin/agent-run c1 "$@"
    else
        command claude "$@"
    fi
}
```

Danach `source ~/.bashrc`. `claude`, `claude --resume <id>` und `claude -c` landen damit in `c1-<ordner>-xxxx`;
Argumente werden durchgereicht. Geprüft: `agent-run` übernimmt für das Konto `c1` keine Rechte-Abschaltung
(`skip_permissions: false` in der Gateway-Konfiguration, `auto_trust: false`), die Sitzung verhält sich also wie das
nackte `claude`. Zum Vergleich `command claude` tippen, wenn es einmal ohne tmux sein soll.

Für die Sitzungen, die heute noch ohne tmux laufen, gibt es zwei Wege: am PC beenden und mit dem Wrapper per
`claude --resume <id>` wieder öffnen, oder in der App im Postausgang „Am PC beenden und hier fortsetzen…“ wählen.

## Vorschlag: `~/.tmux.conf`, damit es sich wie bisher anfühlt

Der Block ergänzt den vorhandenen `notifyd`-Block (`history-limit`, `window-size`):

```tmux
# >>> relay pc >>>
set -g mouse on                                   # Mausrad scrollt im Verlauf, Ziehen markiert
set -s set-clipboard on                           # Markiertes landet per OSC 52 in der Zwischenablage
set -g default-terminal "tmux-256color"
set -as terminal-features ",xterm-256color:RGB"   # Farben wie ohne tmux (Truecolor in Konsole)
set -g status off                                 # keine Statuszeile, sieht aus wie das nackte Terminal
set -sg escape-time 10
set -g focus-events on
# <<< relay pc <<<
```

Einlesen ohne Neustart: `tmux source-file ~/.tmux.conf`. Hinweise:

- Mit `mouse on` übernimmt tmux Markieren und Kopieren: Ziehen mit der Maus markiert, Loslassen kopiert. Ob der Text
  per OSC 52 in der System-Zwischenablage landet, muss Konsole (hier 26.08) erlauben; falls Einfügen in anderen
  Programmen nicht klappt, `wl-clipboard` installieren (`sudo pacman -S wl-clipboard`, Wayland-Sitzung) und diese
  Zeile ergänzen: `bind -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "wl-copy"`. Die native
  Konsole-Markierung geht weiter mit gedrückter Umschalttaste.
- `status off` gilt für alle tmux-Sitzungen, auch die Terminals des Handys (`phone-*`); das Live-Bildschirm-Panel der
  App liest die Pane, nicht die Statuszeile, und ist davon nicht betroffen.
- Rechtsklick öffnet mit `mouse on` das tmux-Menü statt des Konsole-Menüs. Wer das nicht will, lässt `mouse on` weg
  und scrollt mit `Strg-b [` (Pfeiltasten, `q` beendet).

## Aufräumen: was mit tmux-Sitzungen passiert

- **`claude` wird beendet** (`/exit`, Strg-D, Strg-C zweimal): Die tmux-Sitzung endet mit, weil `claude` ihr einziges
  Programm ist (`remain-on-exit` ist aus). Das Terminal zeigt wieder die Shell. Nichts bleibt liegen.
- **Nur das Fenster wird geschlossen** (Konsole-Tab zu, Rechner gesperrt und Fenster weg): Der tmux-Client löst sich,
  die Sitzung und `claude` laufen weiter. Genau so sind die 10 Sitzungen `c1-*` vom 5. und 6. November entstanden
  (vom Handy gestartet oder umgezogen, nie geschlossen). Sie sind kein Fehler, sondern Sitzungen, die weiterlaufen und
  in der App als „Bereit“ erscheinen, mit dem Symbol „Am PC offen“ nur, solange ein Terminal daran hängt.
- **Weiterarbeiten**: am PC `tmux attach -t =c1-martin-xxxx` (Name aus `tmux ls`) oder in der App weitertippen.
- **Schließen**: in der App „Sitzung schließen“ oder „Alle Sitzungen beenden…“ (Abschlussnachricht, Übergabe,
  Beenden), am PC `tmux kill-session -t =c1-martin-xxxx`. Das Gateway kann inaktive Sitzungen auch selbst schließen
  (Auto-Hibernation), läuft bei Martin aber im Probelauf („hibernate (dry-run)“, Schwelle 12 Stunden) und schließt
  nichts. Einschalten wäre eine Konfigurationsänderung am Gateway, die Martin entscheidet.

## Sitzungen ohne tmux: „am PC offen“ erkennbar?

Ja. Ein lebendes `claude` ohne tmux-Pane hat ein Terminal (pty), das kein tmux-Pane ist. Das Gateway meldet solche
Sitzungen als `pc_attached: true`, solange sie leben; `claude --bg`-Sitzungen (ohne eigenes Terminal) und von Agenten
gestartete `claude -p`-Läufe bekommen kein Feld (unbekannt, kein Symbol). Ein Live-Ereignis gibt es dafür nicht, es
ändert sich erst mit dem Ende der Sitzung.
