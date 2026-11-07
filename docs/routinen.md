# Routinen in der iOS-App

Stand: 2026-11-07. Die App zeigt und steuert die Routinen des Gateways wie der Reiter „Routines“ der Android-App
(TeamScreens.kt, TeamUi.kt, TeamModel.kt). Protokoll: PROTOCOL.md des Relay-Repos, Abschnitt „Team, handoffs and
routines“ → „Routines“.

## Was die App kann (ab 0.3.6)

- Menü der Sitzungsliste → „Routinen“: Liste nach Besitzer (Chef zuerst) mit Titel, Beschreibung, Zeitplan (`when`
  auf Deutsch, etwa „werktags 08:00“), nächstem Lauf („nächster Lauf in 3 Std.“) und letztem Lauf (ok, Fehler,
  läuft, noch nie). Schalter an/aus je Routine (`routine_set`).
- Detailansicht: Anweisung, Besitzer, Art, Modus, Zustellung, letzter Lauf mit Zusammenfassung, „Jetzt ausführen“
  (`routine_run`, Ergebnis als Satz: „Fertig: …“, „Fehlgeschlagen: …“, „Läuft…“), bei einem Handoff „Sitzung öffnen“
  (`handoffs {state: all}` liefert den Schlüssel der Sitzung).
- Abschnitt „System“: die systemd-Timer des Benutzers, die keine Routine nennt (`system` aus `routines`), nur Anzeige
  mit nächstem und letztem Lauf und Ergebnis.
- „Neue Routine…“: Martin beschreibt in Worten, was wann laufen soll. Das geht als `team_send {to: chief}` an den Chef
  (Text „Neue Routine: …“ mit der Bitte, den Eintrag vorzuschlagen, `enabled: false` zu setzen und vor dem
  Aktivieren zu fragen).
- Live: das Ereignis `routine_run` ersetzt den letzten Lauf der Routine in der Liste.
- App-Suche: Routinen erscheinen in der Suche der Sitzungsliste (Titel, Beschreibung, Kennung, Zeitplan).
- Ohne `team:`-Block antwortet das Gateway `enabled: false`; die App zeigt „Routinen im Gateway nicht eingerichtet“ mit
  einem Hinweis auf diese Seite. Nichts anderes ändert sich.

Logik in RelayCore (`Routines.swift`: `RoutinesInfo`, `Routine`, `RoutineRun`, `SystemTimer`, `RoutinesText`) mit
Tests (`RoutinesTests`), Oberfläche in `App/Sources/RoutinesView.swift`. Das Mock-Gateway der Simulator-Tests
beantwortet `routines`, `routine_run`, `routine_set`, `team_send` und `handoffs` (Fixture `testing/fixtures/routines.json`),
die Steuerdatei `routines_off` stellt das Gateway ohne Team dar (`InfoTests.test21_Routines`, `test22_RoutinesOff`).

## Befund zum Gateway (Martins Rechner)

- Das Gateway kann Routinen (`gateway/src/notifyd/routines.py`, `team.py`), antwortet aber ohne `team:`-Block in
  `~/.config/notifyd/config.yaml` auf alle Team-RPCs nur `{"enabled": false}`. Martins Konfiguration hat heute die
  Schlüssel `overview`, `poll_fallback_s`, `auto_trust`, `accounts` und keinen `team:`-Block.
- Der `team:`-Block braucht mindestens `roster:` (Pfad einer Roster-Datei mit mindestens einem Mitglied, Pflicht `id`
  und `title`). `routines:` ist optional, ohne sie gibt es keine Routinen, aber die Timer-Liste.
- systemd-Timer: `routines.py` liest `systemctl --user list-timers --all`. Mit dieser Funktion lokal geprüft
  (2026-11-07, 06:10): alle 11 Benutzer-Timer erscheinen, darunter relay-nachtbau, stellen-lauf, stellen-abruf,
  stellen-woche, betriebspruefer, nachtlauf-geschaeftsfuehrer, dreaming-nacht, dreaming-woche, relay-spiegel und zwei
  drkonqi-Timer von KDE. Nennt eine Routine den Timer (`system: <unit>.timer`), steht er mit Titel und Beschreibung
  unter den Routinen statt unter „System“; „Jetzt ausführen“ ist für ihn gesperrt, systemd führt ihn aus.
- „Neue Routine“ ohne Team: `team_send` antwortet `enabled: false`, die App zeigt den Hinweis. Mit Team startet
  das Gateway für den Chef eine eigene Claude-Sitzung (Lead) in seinem `home` mit dem Auftragstext aus `chief.md`
  neben der Roster-Datei (fehlt die Datei, ein kurzer Standardtext). Diese Sitzung schreibt dann in `routines.yaml`
  und fragt zurück. Sie läuft auf dem Hauptkonto und kostet Token wie jede Sitzung.

## Empfehlung: kleinste Team-Konfiguration nur für Routinen

Vorbereitet in `docs/routinen/` (nichts davon ist aktiv):

1. `roster.yaml` → `~/.agents/team/roster.yaml`: ein Mitglied `chief` („Relay Chef“, home `~`, notify `checkin`).
   Optional `~/.agents/team/chief.md` mit Martins Regeln für diese Sitzung (sonst Standardtext des Gateways).
2. `routines.yaml` → `~/.agents/team/routines.yaml`: die bestehenden Timer als `system:`-Routinen mit Titel und
   Beschreibung (relay-nachtbau, stellen-lauf, stellen-abruf, stellen-woche, betriebspruefer,
   nachtlauf-geschaeftsfuehrer, dreaming-nacht, dreaming-woche, relay-spiegel) und eine ausgeschaltete Beispielroutine
   „Wochenrückblick“ (`prompt`, Fr 17:00) für den Chef.
3. `config-team.yaml`: den `team:`-Block ans Ende von `~/.config/notifyd/config.yaml` anhängen.
4. notifyd neu starten (Benutzerdienst). Danach in der App Menü → „Routinen“ prüfen.

Begründung: `~/.agents/` ist Martins Ablage für das Agentensystem, dort liegen schon Regeln, Skills und Memory. Der
Vault passt nicht, weil das Gateway die Datei bei jedem Schalter umschreibt und der Vault synchronisiert wird.
Schritte 3 und 4 ändern Konfiguration und Dienst und laufen nur nach Freigabe (Rückfrage). Nebenwirkungen des Teams,
die mit dem Block mitkommen: Sitzungen tragen `member`/`team_role` (alle fallen auf `chief`), Check-ins um 12:30 und
18:00 melden fertige Routinen als Hinweis, der Standby zählt die Timer in `routines-next.json`. Nichts davon startet
Sitzungen von sich aus; nur „Neue Routine“ und `prompt`-Routinen tun das.

## Prüfung

- RelayCore: `RoutinesTests` (Fixture, Ereignis `routine_run`, `routine_set`, Zeitplan- und Lauftexte, Suche).
- Simulator: `InfoTests.test21_Routines` (Liste, Detail, `routine_run`, „Neue Routine“ → `team_send`),
  `test22_RoutinesOff` (Hinweis ohne Team).
- Gegen das echte Gateway nach der Aktivierung: `swift run relay-smoke <host> <port> <user> <seed> routines` muss
  `enabled: true` und die Timer liefern; `notifyd team routines` am PC zeigt dasselbe.
