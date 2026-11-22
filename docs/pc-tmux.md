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
- Von 0.3.7 bis 0.3.15 gab es den Umzug in tmux auf ausdrückliche Wahl (Knopf „Am PC beenden und hier
  fortsetzen…“ in der Postausgangszeile, danach eine Bestätigung). **Seit 0.3.16 ist der Knopf entfernt** (Martin,
  12.11.2026): Nach der Übernahme startete das Gateway die Sitzung per `claude --resume` in tmux neu, und die blieb an
  der Abfrage „Trust this folder?“ hängen (`auto_trust: false`, das bleibt so). Am 11.11.2026 um 09:35 entstanden so
  zwei hängende Sitzungen. Der Hinweis über der Eingabe nennt jetzt den Weg am PC: „Am PC beenden und mit
  „claude --resume <id>“ neu öffnen, dann geht es in tmux weiter.“ (mit der echten Kennung der Sitzung). Seit dem
  12.11.2026 startet `claude` am PC per Funktion in `~/.bashrc` immer in einer Agenten-tmux-Sitzung.
- Das Gateway kennt `send` mit `move` weiterhin, weil „Alle Sitzungen beenden“ (`wind_down`) es für Sitzungen am PC
  ohne tmux nutzt. Die App sendet `move` nicht mehr.
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

Für die Sitzungen, die noch ohne tmux laufen, gibt es einen Weg: am PC beenden und mit dem Wrapper per
`claude --resume <id>` wieder öffnen (den Befehl mit der Kennung zeigt die App im Hinweis über der Eingabe). Den
Knopf „Am PC beenden und hier fortsetzen…“ gibt es seit 0.3.16 nicht mehr.

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

## Codex seit 0.171: zweite Nachricht vom Handy wurde abgelehnt

Stand 22. November 2026 (Version 0.3.18, Gateway `4cbb059` und `6b9534c` in `~/relay`, Zweig `lokal-clear-beendet`).
Backlog-Eintrag „Codex: Zweite Nachricht am Handy blockiert mit Hinweis auf PC-Sitzung“.

### Befund

Die App war nicht veraltet (Nutzungsprotokoll: iOS 0.3.17, Build 110). Die Ursache lag im Gateway und in einer
Änderung von Codex:

- Seit Codex 0.171 ist die Oberfläche im Terminal (TUI) nur noch ein Fenster auf einen gemeinsamen Hintergrunddienst
  (`codex app-server`, ein Prozess für alle Unterhaltungen). Dieser Dienst hält die Sperrdatei jeder Unterhaltung
  (`~/.codex/thread-writer-locks/<id>.lock`), nicht mehr das TUI.
- Das Gateway fand die tmux-Pane einer Codex-Sitzung über den Prozess, der die Sperre hält. Der Dienst hängt an
  keiner Pane. Ergebnis: Jede Codex-Sitzung galt als „lebt, aber ohne tmux“, also als Sitzung in einem Terminal am
  PC, und `send` lehnte mit „Desktop terminal outside tmux“ ab.
- Die erste Nachricht ging trotzdem durch, weil eine neue Sitzung zuerst als Platzhalter (`tmux-x1-…`) in der Liste
  steht und der Platzhalter die Pane kennt. Sobald Codex die Unterhaltung nach der ersten Nachricht in seinen Index
  schrieb, erschien sie ein zweites Mal unter ihrer echten Kennung, ohne Pane. Im Nutzungsprotokoll vom 22.11. ist
  genau das zu sehen: „gesendet“ an `codex:x1:tmux-x1-zweites-Gehirn-24e4`, 16 Sekunden später „abgelehnt (PC ohne
  tmux)“ an `codex:x1:01a203d5-…`. Am PC lief dafür kein eigenes Fenster, daher der Eindruck „dort ist nichts offen“.
- Nebenbefund: Die Sitzung trug die Prozessnummer des Dienstes. „Sitzung schließen“ vom Handy hätte bei einer solchen
  Sitzung den Dienst beendet und damit alle Codex-Unterhaltungen. Das ist mit behoben.
- Der Dienst hält eine Unterhaltung nach dem Schließen des Fensters noch ein bis zwei Minuten geladen. So lange
  steht sie weiter als laufend in der Liste.

### Behebung im Gateway

- Sitzungen, deren Sperre der Dienst hält, bekommen ihre Pane über die Codex-TUIs in tmux: Steht die Kennung auf der
  Befehlszeile (`codex resume <id>`, so öffnet „Wieder öffnen“), gehört die Pane zu dieser Unterhaltung. Sonst gehört
  eine Unterhaltung zu dem TUI, das kurz vor ihr gestartet ist (höchstens 2 s danach bis 30 s davor, gleicher Ordner,
  das nächste Paar zuerst, jede Pane einmal). Die Entstehungszeit steckt in der Kennung (UUIDv7).
- Eine Sitzung trägt die Prozessnummer ihres TUI oder keine, nie die des Dienstes.
- Ob eine Sitzung ohne Pane arbeitet, liest das Gateway am Ende der Verlaufsdatei ab (`task_started` ohne
  `task_complete`).

### Geprüft

- Gateway-Tests: 1072 bestanden, 13 übersprungen, davon 14 neu in `tests/test_codex_appserver.py`.
- Echter Durchlauf `testing/gateway_codex_beide_geraete.py` gegen den geänderten Gateway-Code (eigener Daemon im
  Skript, Codex 0.171, Konto `x1`): Sitzung wie vom Handy gestartet, erste Nachricht an den Platzhalter, danach hat
  die echte Sitzung Pane und tmux-Namen. Zweite und dritte Handy-Nachricht jeweils nach fertiger Antwort: angekommen
  und beantwortet. Eine Sitzungs-ID, jede Nachricht genau einmal im Verlauf.
- Am Live-Dienst nach dem Neustart (22.11., 16:45): Martins drei Codex-Sitzungen vom Nachmittag stehen mit ihren
  tmux-Sitzungen `x1-zweites-Gehirn-…` in der Liste, die doppelten Platzhalter sind weg.
- Nicht geprüft: am iPhone selbst.

## Codex: dieselbe Unterhaltung am Rechner und am Handy

Stand 22. November 2026 (Version 0.3.18). Backlog-Eintrag „Dieselbe Codex-Unterhaltung am Rechner und am Handy
bedienen“: beide Geräte sehen dieselbe Unterhaltung und schreiben darin weiter, ohne Übergabe, Beenden oder
Aussperren.

### Wie es jetzt läuft

Codex bringt den passenden Weg selbst mit: `codex queue --thread <id> --message <text> --resume` reiht eine Nachricht
in eine bestehende Unterhaltung ein. Der Dienst arbeitet eingereihte Nachrichten nacheinander in derselben
Unterhaltung ab, gleich, ob sie aus dem TUI, aus der PC-App oder vom Handy kommen. Das Gateway nutzt diesen Weg für
jeden normalen Text an eine Codex-Sitzung, die der Dienst hält:

| Wo die Unterhaltung läuft | Handy liest mit | Handy schreibt | Slash-Befehle, Tasten, Live-Bildschirm |
|---|---|---|---|
| In tmux (aus der App gestartet, „Wieder öffnen“, `agent-run x1`) | ja | ja, über `codex queue` | ja, über die Pane |
| Am PC im Terminal ohne tmux (nacktes `codex`) | ja | ja, über `codex queue` | nein |
| PC-App (ChatGPT/Codex Desktop), gleicher Ordner `~/.codex` | ja | ja, über `codex queue` (nicht mit offener App geprüft) | nein |
| Beendet (kein Fenster mehr offen) | ja | ja, Codex setzt die Unterhaltung im Dienst fort | nein, erst nach „Wieder öffnen“ |

- Zeitgleiche Eingaben: Ein Text vom Handy landet nicht mehr im Eingabefeld des TUI. Ein Entwurf, der am PC gerade
  getippt wird, bleibt unberührt. Läuft ein Zug, startet die Nachricht danach. Es gibt einen Agentenlauf je
  Unterhaltung, weil alles durch denselben Dienst geht. Die Absage „arbeitet gerade“ entfällt für solche Nachrichten.
- Die Rechteprüfung bleibt, wie sie ist: `codex queue` übernimmt Modell und Einstellungen der Unterhaltung, das
  Gateway gibt keine Schalter zum Umgehen mit (`skip_permissions: false`). Freigaben, die Codex braucht, erscheinen
  in tmux wie bisher als Auswahlkarte in der App.
- In der App (ab 0.3.18): Eine Unterhaltung ohne tmux trägt vom Gateway `queue_input`. Die App zeigt dann nicht
  mehr „vom Handy nur mitlesen“, sondern „Auch am PC offen (ohne tmux): Nachrichten gehen in dieselbe Unterhaltung
  und laufen der Reihe nach. Slash-Befehle und Live-Bildschirm gibt es hier nicht.“ Früher abgelehnte Nachrichten
  („ohne tmux“) gehen innerhalb einer Stunde von selbst hinaus. Mit der App 0.3.17 klappt das Schreiben ebenfalls,
  sie zeigt in diesem Fall nur noch den alten Hinweis.

### Geprüft (echter Durchlauf am 22.11.2026, `testing/gateway_codex_beide_geraete.py`)

- Start am Handy (tmux): Handy, Handy, Handy (mit Entwurf „ENTWURF-AM-PC“ im Eingabefeld des TUI), PC getippt,
  Handy. Fünf Nachrichten, fünf Antworten, eine Sitzungs-ID, jede Nachricht genau einmal im Verlauf, der Entwurf
  stand danach unverändert im Eingabefeld.
- Start am PC im Terminal ohne tmux (pty wie ein Konsole-Fenster): am PC getippt, dann zweimal Handy. Drei
  Nachrichten, drei Antworten, eine Sitzungs-ID, jede genau einmal. Die Sitzung meldet `queue_input`, keine
  Prozessnummer, kein „Terminal ohne tmux“.
- Von Hand vorab: zwei Nachrichten direkt hintereinander eingereiht, während die erste lief. Die zweite startete
  nach der ersten (vier Züge, vier Antworten in Reihenfolge). Nach dem Schließen des TUI nahm dieselbe Unterhaltung
  eine weitere Nachricht an und beantwortete sie.

### Grenzen, offen dokumentiert

- **PC-App:** Die App `/usr/lib/chatgpt` legt ihre Unterhaltungen im selben Ordner ab (im Index stehen acht mit
  Herkunft „Codex Desktop“, zuletzt vom 9.11.2026). Das Handy listet sie und kann hineinschreiben. Ob die offene
  PC-App eine vom Handy eingereihte Nachricht sofort anzeigt, ist nicht geprüft: Die App lief während des Nachtbaus
  nicht, und ohne Martin lässt sie sich nicht bedienen.
- **Freigaben ohne offenes Fenster:** Braucht Codex in einer Unterhaltung ohne tmux eine Freigabe, erscheint sie am
  PC (TUI oder PC-App), nicht in der Relay-App. Ist dort kein Fenster offen, wartet der Lauf vermutlich, bis jemand
  die Unterhaltung öffnet. Nicht geprüft.
- **`/new` und `/resume` im TUI:** Wechselt man im TUI in eine andere Unterhaltung, kennt das Gateway die Pane nur
  für die Unterhaltung, mit der das TUI gestartet ist. Text vom Handy kommt trotzdem in der richtigen Unterhaltung
  an (er geht über die Kennung, nicht über die Pane). Live-Bildschirm und Slash-Befehle zeigen in dem Fall auf das
  Fenster, das inzwischen etwas anderes zeigt.
- **Zwei neue Sitzungen im selben Ordner innerhalb weniger Sekunden:** Die Zuordnung nach Startzeit nimmt das
  jeweils nächste Paar. Für Text ist das ohne Belang, für Live-Bildschirm und Tasten könnten zwei Sitzungen
  vertauscht sein. Nicht beobachtet.
- **Schließen vom Handy** geht nur für Sitzungen in tmux. Eine Unterhaltung ohne tmux gehört dem Fenster am PC.
- **Älteres Codex** (TUI hält die Sperre selbst): Verhalten wie bisher, ohne tmux lehnt das Gateway ab.
- **Claude** ist unverändert: in tmux tippen beide Geräte in dieselbe Sitzung, ohne tmux liest das Handy mit.
- Am iPhone ist der Ablauf noch nicht geprüft.
