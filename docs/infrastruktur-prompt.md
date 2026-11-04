# Prompt für Christophers KI-Assistenten (zum Einfügen)

Der folgende Block ist direkt in die Sitzung von Christophers eigenem KI-Assistenten (Claude Code in seinem Setup) zu kopieren. Er ist auf Deutsch geschrieben, weil Martin Deutsch spricht, die Dateien und Befehle bleiben englisch.

---

Hallo, hier fragt Martin (er nutzt Relay, github.com/chart21/relay, und baut gerade eine native iOS-Version davon). Die iOS-App spricht dasselbe Protokoll wie die Android-App (PROTOCOL.md v2, JSON-Zeilen über SSH zum Gateway `notifyd`). Martins Gateway ist bisher ein schlichtes Setup (zwei Konten, `claude` und `codex`, dazu der Overview-Agent). Er möchte morgen früh die Infrastruktur nachbauen, die hinter den unten aufgelisteten Funktionen steckt, und braucht dafür eine genaue Dokumentation aus deinem Setup, weil du weißt, wie es bei Christopher wirklich läuft.

**Deine Aufgabe:** Dokumentiere für jede unten genannte Funktion präzise, was im Hintergrund läuft, damit Martin es nachbauen kann. Schau dazu in das Relay-Repository (`gateway/src/notifyd/`, `android/app/src/main/java/dev/relay/app/`, `PROTOCOL.md`), in `~/.config/notifyd/` (config.yaml, machines.json, fritz.env und weitere Dateien), in die Projekte `personal/`, `assistant/` und `creative/`, in `~/agent-tools`, `~/agent-notes`, in die systemd-User-Units und Timer (`systemctl --user list-units`, `list-timers`), in crontab, auf den Raspberry Pi und in die Docs-Pläne (`docs/plan-2026-10-23-alarm-brief-power.md`, `docs/plan-2026-10-23-standby.md`, `docs/plan-2026-10-26-team.md`, `docs/app.md`). Wo du etwas nicht findest oder nur vermutest, schreibe das ausdrücklich ("nicht gefunden", "vermutet"), statt zu raten.

## Ausgabeformat

Eine einzige Markdown-Datei `relay-infrastruktur.md`, gegliedert nach den Funktionen unten (Abschnitt je Funktion, gleiche Nummern F1 bis F15). Jeder Abschnitt enthält, soweit zutreffend:

1. **Zweck und Datenfluss** in 3 bis 6 Sätzen (Handy -> Gateway -> was?). Wer ruft wen auf, über welchen Port und welches Protokoll.
2. **Was läuft wo:** Pi, Desktop, Laptops, Handy, externe Dienste. Je Komponente: Hostname-Rolle, Betriebssystem, Programm, Version (soweit bekannt).
3. **Dateien:** Pfad, Zweck, Format mit anonymisiertem Beispiel (JSON, YAML, Env), Rechte (`chmod`), ob die Datei im Repo steht oder nur lokal liegt.
4. **Config in `~/.config/notifyd/config.yaml`:** die genauen Schlüssel dieser Funktion als YAML-Beispiel mit Platzhaltern.
5. **Umgebungsvariablen und Geheimnisse:** Name und Zweck, Wert ersetzt durch `<PLATZHALTER>`. Wo das Geheimnis liegt (Datei, Keyring), nie der Wert selbst.
6. **systemd-Units, Timer, cron:** vollständiger Inhalt der Unit-Dateien (ohne Geheimnisse), Aktivierungsbefehle.
7. **Skripte und Programme:** Pfad, Aufruf, Ein- und Ausgabeformat (stdout-JSON), Abhängigkeiten (apt oder pacman, pip, npm).
8. **Externe APIs und Konten:** URL, ob Schlüssel oder Konto nötig, Kosten, Limits, Datenschutz.
9. **Netzwerk:** Ports, Bindung (127.0.0.1 oder LAN), Firewall, WireGuard, Wake-on-LAN.
10. **Installationsschritte** als nummerierte Befehle, die Martin auf einem frischen Arch-Linux-Desktop (und, wo nötig, auf einem Raspberry Pi OS) ausführen kann, mit Prüfbefehl nach jedem Schritt ("so siehst du, dass es läuft").
11. **Persönlich oder generisch:** Was ist Christophers eigene Sache (München, MVG, seine Kalender, seine Mailkonten, sein Projektordner), was ist allgemein nutzbar? Für die persönlichen Teile: was Martin austauschen muss, mit Beispielwert-Format.
12. **Abhängigkeiten zwischen den Funktionen** (z. B. braucht F9 den Pi aus F7).

Am Ende:

- Eine **Reihenfolge zum Nachbauen** (was zuerst, was hängt woran), mit grober Zeitschätzung je Schritt.
- Eine **Liste aller Geheimnisse und Konten**, die Martin selbst anlegen muss (ohne Werte).
- Eine **vollständige Beispiel-`config.yaml`** mit allen Blöcken dieser Funktionen, Geheimnisse durch Platzhalter.
- Eine Liste dessen, was **nur im Gateway-Code steht und nicht in PROTOCOL.md** (z. B. `clean_dictation`, `clean_warm`, `phone_request_status`, `session_settings`, `interview_check`).

Wichtig:

- **Keine Geheimnisse ausgeben.** Tokens, Passwörter, Schlüssel, Webhook-Secrets, Mailzugänge, Cookies, Session-IDs immer durch `<PLATZHALTER>` ersetzen. Gib weder den Inhalt von `.credentials.json`, `fritz.env`, `kuma-webhook.secret`, `desk-inbox.token`, `profile.json` noch von Browser-Profilen aus.
- Martin hat keine Berechtigung auf Christophers Rechnern. Du dokumentierst nur und änderst nichts an laufenden Systemen.
- Keine Gedankenstriche im Text (Punkt, Komma, Klammern verwenden). Befehle und Code in Codeblöcken.
- Knapp und kopierbar. Keine Erklärungen zu Dingen, die im Repository schon stehen, dort nur verweisen (Datei und Abschnitt).

## Die Funktionen

Die Gateway-Dateien liegen unter `gateway/src/notifyd/`, die Android-Dateien unter `android/app/src/main/java/dev/relay/app/`. rpc-Namen stehen so, wie sie in PROTOCOL.md heißen.

### F1: Morgen-Briefing und Züge (MVG, Wetter)

- rpc `brief` (`fresh`, `last`), Event `notice` mit `tag: "brief"` (Titel "Morgen-Briefing", täglich um `brief.at`, Standard 08:00), `hello_ok.config.brief` `{lat, lon, from_id, from_name, to_id, to_name, line}`.
- Gateway: `brief.py`, `parcels.py` (Paketdaten im Briefing), `teambrief.py` (Team-Sätze), `daemon.py` (`publish_brief`, `_brief_loop`, `rpc_brief`). Tests: `gateway/tests/fixtures/brief/`.
- Android: `Brief.kt`, `BriefScreen.kt`, `Trains.kt` (fragt MVG direkt vom Handy), `Alarm.kt` (Wecker liest das Briefing).
- Externe Quellen: Bright Sky (Wetter), MVG `bgw-pt/v3/routes` und `.../messages` (Abfahrten, Störungen). Dokumentiere: wie die Stations-IDs (`from_id`, `to_id`) ermittelt werden, welche Linie, wie `parcels.py` an seine Daten kommt (welcher Dienst, welche Datei).
- Frage: Welche Schlüssel stehen in Christophers `brief:` Block, und was davon ist reiner Ort (München)?

### F2: Kalender (Tab "Calendar")

- rpc `calendar` (`from`, `days`, `refresh`), Gateway `agenda.py`, `owacal.py`, Android `Calendar.kt`.
- Quellen: `~/workspace/personal/bin/cal` (`cal agenda`, `cal sync`) und Config `calendar: {sources, hide, owa, owa_every_min}`; Outlook-on-the-web-Offline-Caches anderer Rechner (per SSH kopiert).
- Dokumentiere: Wie funktioniert `personal/bin/cal` (welche Kalender, welches Protokoll: CalDAV, ICS-Feeds, Google?), wie liegen die Zugangsdaten, welche Cron- oder Timer-Syncs laufen, wie kommt der OWA-Cache zustande (Browser-Profil, Pfad, Format) und welche SSH-Hosts werden gelesen.

### F3: News (YouTube und X)

- rpc `news` (`limit`, `refresh`, `source`, `query`), `news_post` (`id`, `page`), `news_summary` (`id`, `start`). Gateway `daemon.py` (`_news_tool`, ruft `~/workspace/personal/bin/news`). Android `News.kt`, `NewsPost.kt`.
- Dokumentiere: `personal/bin/news` (Unterbefehle `fetch`, `enrich_x` und weitere), woher die YouTube-Kanalliste und die X-"Following"-Liste kommen, den Agent-Browser (Profil, Anmeldung bei X, wie er headless läuft), X-Embed-Endpunkt, das Speicherformat und den Aufbewahrungszeitraum (30 Tage), den Skill `youtube` für `news_summary` (Aufruf `claude-pool run auto`, User-Unit `yt-summary-<id>`).

### F4: Posteingang (Mail und Chats)

- rpc `inbox_feed`, `inbox_chat`, `inbox_search`, `inbox_mail`, `inbox_mail_reply`, `inbox_mail_delete`, `inbox_mail_suggest`, `inbox_mail_keep`, `inbox_mail_delete_many`. Gateway `inbox.py`, `mailsuggest.py`, `deskinbox.py`, `deskinbox_fake.py`, `phonebridge.py`. Android `Inbox.kt`, `InboxFormat.kt`. Desktop-Seite `notifyd desk-inbox serve` (127.0.0.1:8796, `desktop/inbox/`).
- Dokumentiere: den Mailindex (`personal/bin/mail`, Indexformat, wie er gefüllt wird: mbsync, offlineimap, notmuch, eigener Index?), die Konten (Gmail, Outlook, GMX, Uni, WEB.DE: Protokoll, App-Passwort oder OAuth, nur Typ nennen), das Archiv (2020 bis 2026-07), `personal/bin/mail-act` und das Thunderbird-Add-on `personal/tools/thunderbird/relay-mail` (Installation, wie Antworten und Löschen tatsächlich ausgeführt werden), `~/.local/state/notifyd/inbox-keep.json`, Cron und Timer zum Aktualisieren des Index. Chats kommen aus der Android-Telefon-Bridge (`inbox_put` `kind: notification|sms`, Ordner `$NOTIFYD_INBOX`): nur kurz erwähnen, dass die iOS-Version dafür keine Quelle hat.

### F5: Team, Aufgaben, Routinen, Check-ins

- rpc `team`, `team_send`, `team_open`, `handoffs`, `handoff`, `handoff_set`, `handoff_cancel`, `handoff_wait`, `handoff_done`, `team_worker`, `routines`, `routine_run`, `routine_set`, `checkin_add`, `session_peek`, `session_reply`; Events `handoff`, `routine_run`, Notices mit `tag` `handoff` und `checkin`. Gateway `team.py`, `handoffs.py`, `routines.py`, `teambrief.py`, `team_mcp.py`, `waiting.py`; Android `Team.kt`, `TeamModel.kt`, `TeamScreens.kt`, `TeamUi.kt`.
- Config `team: {roster, routines, rotate: {chief_daily_at, max_transcript_kb}, waiting: {enabled, first_min, sweep_min, after_min}}`; `team/roster.yaml` und `team/routines.yaml` im Projekt `assistant`; Zustand in `~/.local/state/notifyd/` (`handoffs.jsonl`, `waiting.json`, `routines-next.json`); `deadlines.json`; `spend.log` (Spalten Datum, Agent, Dienst, EUR, Was).
- Dokumentiere: Aufbau von `roster.yaml` (alle Felder: `id`, `name`, `avatar`, `title`, `home`, `folders`, `topics`, `routing`, `notify`, `charter`, `model`, `effort`, `spend`) mit zwei anonymisierten Beispielmitgliedern, Aufbau von `routines.yaml` (`when`-Formate, `kind`, `mode`, `deliver`, `run: builtin:brief`) mit Beispielen, die Charter-Dateien der Leads (Struktur und Länge, nicht der private Inhalt), den Team-MCP-Start (`python -m notifyd mcp --member <id>`), die System-Timer, die `routines` als `system` anzeigt, das Skript, das `checkin_add` aufruft.

### F6: Uptime-Alarme (Uptime Kuma auf dem Pi)

- Event `alert` `{monitor_id, monitor, status, msg, since, url}`; Android `Uptime.kt`; Config `uptime: {listen: "<LAN-Adresse>:8767"}`; Secret `~/.config/notifyd/kuma-webhook.secret`; Pi-Dienst `kuma-forward` (Port 8768).
- Dokumentiere: Uptime-Kuma-Installation auf dem Pi (Docker oder npm, Version), die Monitore (nur Typen, nicht Christophers Domains), die Webhook-Benachrichtigung (URL-Muster `/kuma/<secret>`, Body-Format), `kuma-forward` (Code, Unit, wie er den schlafenden Desktop weckt und weiterleitet), `kuma_pending`, wie das Gateway den Webhook-Empfänger startet (Port, Bindung, Firewall), welche Monitore ausgelassen werden ("Desktop (archlinux)").

### F7: Raspberry Pi, Desktop wecken, Standby und Snapshot

- Pi-Befehle (SSH-Forced-Command `/usr/local/bin/wake-desktop`): `wake`, `status`, `snapshot`; `hello_ok.config.pi {host, port, user, host_key}`; Events `desktop_sleep`; rpc `power_off`, `standby`, `power_status`; Konfig `restore: {after_boot: true}`. Gateway `sleepwatch.py`, `daemon.py` (`rpc_standby`, `rpc_power_off`, `_snapshot_live`), Android `PiClient.kt`, `DesktopPower.kt`, `Standby.kt`, `Outbox.kt`, `NetworkMonitor.kt`. Pläne: `docs/plan-2026-10-23-standby.md`.
- Dokumentiere: das Skript `wake-desktop` vollständig (Wake-on-LAN, wie `status` und `snapshot` antworten, wo die Daten im Pi-RAM liegen), die `authorized_keys`-Zeile des Handys auf dem Pi (Optionen), den Sleep-Hook des Desktops (logind `PrepareForSleep`, systemd-Sleep-Skript, was er dem Pi schickt: `desktop_state`, Snapshot, ca. 150 kB), das Sudoers-Fragment für `systemctl poweroff` und `systemctl suspend`, Wake-on-LAN-Einstellungen des Desktops (BIOS, `ethtool`, `nmcli`), `desktop-next-wake` und `routines-next.json` (RTC-Wake zur nächsten Routine), `~/.local/state/notifyd/` Boot-Snapshot für `restore`.

### F8: Hosted (Übersicht aller gehosteten Dienste)

- rpc `hosted`, SSH-Kanal `tunnel <port>`, Gateway `hosted.py`, Config `hosted:`, Registry `~/agent-notes/hosted.json`, Android `Hosted.kt`.
- Dokumentiere: das Registry-Format (Felder `id`, `name`, `owner`, `host`, `port`, `pi_port`, `kind`, `phone`, `path`, `show`, `check`, `unit`, `folder`) mit drei anonymisierten Beispielen (Webseite, VNC, lokaler Dienst), den Pi-Teil (Reverse Proxy, Login, Token, wie "Private Daten" geschützt sind), wie Zertifikatsablauf und Letzter-Deploy ermittelt werden, `bind`-Erkennung der lauschenden Ports.

### F9: Laptops und VPN

- rpc `machines`, `machine_power` (`wake|sleep|power_off`), `vpn` (`status|on|off`), Gateway `machines.py`, Datei `~/.config/notifyd/machines.json` `{machines:[{id, name, ssh, mac, wake, broadcast?, vpn?:{start, stop, check}}]}`, Android `Laptops.kt`.
- Dokumentiere: ein anonymisiertes `machines.json`, die SSH-Config-Einträge (`~/.ssh/config`: nur Muster), die NOPASSWD-Sudoers-Regeln auf den Laptops (genau die zwei Befehle), Wake-on-WLAN-Voraussetzungen, das VPN-Skript (`start`, `stop`, `check` mit den Wörtern `up` und `reachable`, tmux-Sitzung, 2FA-Push).

### F10: Heim-WLAN per FRITZ!Box

- rpc `wifi`, `wifi_set` (`which`, `on`, `confirm`, `dry_run`), Gateway `wifi.py`, Datei `~/.config/notifyd/fritz.env` (`FRITZ_HOST`, `FRITZ_USER`, `FRITZ_PASSWORD`, `chmod 600`), Android `Wifi.kt`.
- Dokumentiere: welche FRITZ!Box-Einstellungen nötig sind (TR-064 aktiv, eigener Benutzer mit welchen Rechten, Port 49000, HTTP-Digest), wie `main` und `guest` bestimmt werden, die Logik "an stellt die vorher aktiven Bänder wieder her". Nur relevant, wenn Martin eine FRITZ!Box hat; kurz halten.

### F11: Jarvis Live (Gemini) und Sprach-Wake auf PC und Laptops

- SSH-Kanal `voice` (`hello_ok.config.voice: "live"`, Datei `~/.config/notifyd/jarvis-live`), Programm `creative/glasses/demo/jarvis.py` (127.0.0.1:8793, Funktion `phone_voice`), rpc `wake_claim`, `wake_release`, `speak`, `jarvis_warm`, `voice_timing`; Programm `tools/wake-listen.py` (PC und Laptops), `speech_out.py` (Kokoro `bm_george` englisch, Piper Thorsten deutsch). Android `LiveVoice.kt`, `Assistant.kt`.
- Dokumentiere: Gemini-Live-Zugang (Modell, API-Schlüssel oder Vertex, Kosten), Start von `jarvis.py` (systemd-Unit, Abhängigkeiten, Audioformate 16 kHz s16le rein, 24 kHz s16le raus), die Wake-Word-Erkennung auf PC und Laptops (openWakeWord, Mikrofon, Dienst), die Sprachausgabe (Kokoro und Piper installieren, Modelldateien).

### F12: Mock-Interview vom Handy

- rpc `start_interview` (`mode: audio|video`, `display`, `speaker`, `restart`), `stop_interview`, `interview_check`; Event `interview_call` (`audio: true` oder `url`); SSH-Kanal `interview` (16 kHz rein, 24 kHz raus); Gateway `interview.py`; Config `interview: {command, displays, speakers, viewers, viewer_workspace}`; Android `Interview.kt`.
- Dokumentiere: das Trainerprogramm, das `interview.command` startet (Pfad, Argumente, was `audio` und `video` ändern), i3-Workspace und VNC für `viewers`, Audio-Tunnel zum Handy (`interview.bridge`), Feedback-Speicherort.

### F13: Claude-Limits, Prognose, Aufteilung (claude-pool)

- rpc `usage` (`refresh`, `renew`), `usage_split` (`alias`), Prognose `windows[].forecast`, `extras`, Gateway `usage.py`, `usagesplit.py`, `tokens.py`, `gone.py`, `cloud.py`, Hilfsprogramm `~/.config/notifyd/claude-pool` (`NOTIFYD_CLAUDE_POOL`), Android `AccountsScreen.kt`, `AccountSplit.kt`, `Cloud.kt`.
- Das ist der wichtigste Punkt für Martin: ohne `claude-pool` liefert `usage` für Claude-Konten nur den Fehler "usage helper unavailable". Dokumentiere das Skript vollständig (Funktionen, die das Gateway importiert: `usage(home)`, `plan(home)`, `renew(alias, home)`, `pick()` und alle weiteren), den genutzten Endpunkt (`api/oauth/usage`), wie der Token gelesen wird (`<home>/.credentials.json`, nur den Pfad nennen), die Grenzwerte (`CLAUDE_POOL_SESSION_MAX`, `CLAUDE_POOL_WEEKLY_MAX`, `CLAUDE_POOL_END_MAX`), `claude-pool run auto` (für Zusammenfassungen und `news_summary`), `usage-history.jsonl` (Format, 15-min-Takt, 14 Tage), `accounts-gone.json`.

### F14: Telefon-Bridge-Gegenstelle auf dem PC (nur zur Einordnung)

- rpc `inbox_put`, `inbox_recent`, `phone_request`, `phone_request_status`, `send_result`, `location_result`, `notice`, `phone_presence`; CLI `notifyd phone notify|send-message|approve|location|status|presence|log`; Gateway `phonebridge.py`, `phonepresence.py`; Ablage `$NOTIFYD_INBOX/<kind>/<YYYY-MM-DD>.jsonl`.
- Für Martin ist nur der Teil interessant, der ohne Android-Bridge funktioniert: `notifyd phone approve --kind mail|invite|post|order|payment` (Freigaben, die ein iPhone bestätigen kann) und `notifyd phone notify` (Hinweise). Dokumentiere, welche Skripte und Agenten diese Befehle aufrufen (Beispiele), und was die Gegenstelle erwartet.

### F15: Autofill-Profil, Wecker, Avatare (kleine Dinge)

- rpc `profile_get`, `profile_set`, Datei `~/.config/notifyd/profile.json` (chmod 600, Gateway `profile.py`, nur das Format der Schlüssel dokumentieren, keine Werte); `hello_ok.config` Blöcke `avatars`, `avatar_colors`, `avatar_topics` (Config-Schlüssel, Beispiel mit zwei Einträgen); Config `digest: {at}`, `quiet_hours`, `quota: {notices, margin_min, week_unused_pct}`, `hibernate: {mode, idle_hours, pressure_idle_hours, pressure_mb, max_per_pass, keep}`, `context: {window, warn_pct, high_pct}`, `phone_night`, `vim`, `desk`.
- Dokumentiere nur, welche dieser Config-Blöcke Christopher tatsächlich gesetzt hat und mit welchen Werten (anonymisiert).

## Zusätzlich, als gemeinsamer Abschnitt "Grundlage"

1. Die komplette Liste der Dateien in `~/.config/notifyd/` und `~/.local/state/notifyd/` mit Zweck und Rechten (keine Inhalte außer bei Konfigurationsdateien ohne Geheimnisse).
2. Alle systemd-User-Units und Timer, die zu Relay gehören (`notifyd.service`, `yt-summary-*`, Kuma-Forward auf dem Pi usw.), mit Inhalt.
3. Alle Programme außerhalb des Repos, die das Gateway per Pfad aufruft: `~/workspace/personal/bin/{cal,mail,mail-act,news,thunderbird-session}`, `~/agent-tools/bin/*`, `~/.config/notifyd/bin/{mail,journal}` (`NOTIFYD_MAIL_CLI`, `NOTIFYD_JOURNAL_CLI`), `claude-pool`, `router/CLAUDE.md`, `router/voice-vocab.txt`.
4. Welche Teile davon auch ohne Pi, ohne `personal/`-Projekt und ohne Team laufen (Mindestsetup), und welche Reihenfolge du Martin für den Aufbau empfiehlst.

Danke. Bitte antworte mit der fertigen Markdown-Datei.
