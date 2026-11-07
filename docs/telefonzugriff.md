# Telefonzugriff für Agenten (Konzept für v0.4.0, Stufe 1 in 0.3.11)

Stand: 7. November 2026. Konzept aus dem Nachtbau 10:51, von Martin am 7. November freigegeben. **Stufe 1 ist seit
Version 0.3.11 gebaut** (Nachtbau 19:04, siehe „Umsetzung Stufe 1“ unten; das Konzept nannte 0.4.0, die Nachtbau-Regel
zählt die Patch-Stufe hoch). Stufe 2 und 3 erst nach Martins Rückmeldung zu Stufe 1.

## Ziel

Agenten sollen Dinge am iPhone selbst erledigen können, statt Martin zu schicken („schau mal in Drive nach“, „schick mir
das Foto von gestern“, „wie voll ist der Akku“). Relay ist dafür die Brücke: Der Agent fragt über das Gateway, die App
führt aus, Martin sieht und bestätigt, was nötig ist.

## Was iOS grundsätzlich nicht erlaubt

- Keine App darf andere Apps fernsteuern, den Bildschirm lesen oder bedienen, Tipps simulieren oder
  Systemeinstellungen ändern (Sandbox). iPhone-Synchronisierung per Bildschirmspiegelung gibt es nur von macOS aus.
- Keine dauerhafte Hintergrundausführung. Relay hört nur, solange die App im Vordergrund ist oder kurz danach
  (Hintergrundaufgabe, rund 30 s; dazu Hintergrundabruf, den iOS selbst taktet).
- Ohne bezahltes Entwicklerkonto keine Push-Mitteilungen über Apple (APNs). Das Gateway kann die App also nicht
  aufwecken. Befehle warten im Gateway, bis die App das nächste Mal verbunden ist (wie heute `send_request`).

Folge: Der Telefonzugriff ist „asynchron mit Wartezeit“. Ein Agent stellt einen Befehl und wartet mit Frist; ist die App
zu, bekommt er `pending` und kann Martin per Hinweis bitten, Relay kurz zu öffnen.

## Drei Wege

1. **Daten mit iOS-Berechtigung:** Fotos, Dateien (Dateien-App mit iCloud Drive, Google Drive und anderen Anbietern),
   Kontakte, Kalender und Erinnerungen, Standort, Zwischenablage, Geräteinfos.
2. **Kurzbefehle als Brücke:** Relay startet benannte Kurzbefehle und bekommt ihr Ergebnis zurück. Damit erreicht der
   Agent alles, was Kurzbefehle können (Fokus, Wecker, HomeKit, Nachrichten mit Bestätigung, Apps mit eigenen Aktionen).
3. **Gateway-Werkzeug:** `notifyd phone do …` und ein MCP-Werkzeug schicken einen Befehl aus dem festen Katalog ans
   Handy und warten auf die Antwort.

## Befehlskatalog je Stufe

Jeder Befehl hat einen festen Namen und feste Felder. Freie Befehle (Skripte, beliebige URLs) gibt es nicht.

### Stufe 1: Lesen (Geräteinfos, Dateien, Fotos)

| Befehl | Was er liefert | iOS-Berechtigung | Info.plist |
|---|---|---|---|
| `device_info` | Akku (Stand, lädt), freier Speicher, iOS-Version, Gerätemodell, Relay-Version, Netz (WLAN/Mobil), Fokus nicht lesbar | keine | keine |
| `files_list {folder, path?}` | Dateinamen, Größe, Datum in einem freigegebenen Ordner | einmalige Ordnerfreigabe per Auswahldialog (`UIDocumentPickerViewController` für Ordner), danach Lesezeichen mit Sicherheitsbereich (security-scoped bookmark) | keine (Auswahldialog braucht keinen Eintrag) |
| `files_get {folder, path}` | eine Datei, hochgeladen in den Upload-Ordner des Gateways (wie Anhänge heute), höchstens 100 MB | wie oben | keine |
| `photos_recent {count, since?}` | Liste der letzten Fotos (Datum, Ort falls vorhanden, Größe, Kennung) ohne Bilddaten | Fotos lesen (bei iOS 17 „Begrenzter Zugriff“ möglich) | `NSPhotoLibraryUsageDescription` (vorhanden, Text anpassen) |
| `photos_get {id, max_px?}` | ein Foto, verkleinert auf 2048 px wie heute, hochgeladen | wie oben | wie oben |
| `clipboard_get` | Text der Zwischenablage | iOS fragt bei jedem Lesen selbst („Einsetzen erlauben“), nur im Vordergrund | keine |
| `location` | gibt es schon (`location_request`) | Standort beim Verwenden | vorhanden |

Ordnerfreigaben: In den Einstellungen „Telefonzugriff → Ordner“ wählt Martin einen oder mehrere Ordner (zum Beispiel
„Google Drive/Bewerbungen“, „iCloud Drive/Scans“). Jeder bekommt einen kurzen Namen, den der Agent als `folder` nutzt.
Google Drive erscheint nur, wenn die Google-Drive-App installiert ist und in der Dateien-App als Speicherort
aktiviert ist. Dateien, die nur in der Cloud liegen, lädt iOS beim Lesen nach (`NSFileCoordinator`), das kann dauern.

### Stufe 2: Kurzbefehle

| Befehl | Was passiert | Voraussetzung |
|---|---|---|
| `shortcut_run {name, input?}` | Relay öffnet `shortcuts://x-callback-url/run-shortcut?name=…&input=text&text=…&x-success=relay://shortcut-result?id=…&x-error=…&x-cancel=…`, die Kurzbefehle-App läuft und springt zurück; das Ergebnis kommt über die Rücksprung-URL | URL-Schema `relay` (`CFBundleURLTypes`, neu), App im Vordergrund, Name steht auf der Freigabeliste |
| `shortcut_list` | die freigegebenen Kurzbefehle (Name, Beschreibung, ob schreibend) | keine |
| App Intent „Ergebnis an Relay“ | Kurzbefehle können Text oder Datei an Relay geben, Relay leitet es mit der Befehlskennung ans Gateway | App Intents (gibt es schon für Jarvis), keine Berechtigung |

iOS kann die Liste aller Kurzbefehle nicht auslesen. Darum pflegt Martin in Relay eine Freigabeliste: Name, kurze
Beschreibung, Häkchen „verändert etwas“ (dann Bestätigung nötig). Kurzbefehle laufen nur im Vordergrund und schalten
sichtbar in die Kurzbefehle-App um. Für einen Agenten heißt das: nur, wenn Martin Relay gerade offen hat.

### Stufe 3: Schreiben (immer mit Bestätigung)

| Befehl | Was passiert | iOS-Berechtigung | Info.plist |
|---|---|---|---|
| `calendar_add {title, start, end, …}` | Termin anlegen (Kalender wählbar, Standard iCloud „Privat“) | Kalender, nur Schreiben reicht (iOS 17 `requestWriteOnlyAccessToEvents`) | `NSCalendarsWriteOnlyAccessUsageDescription` |
| `calendar_list {from, to}` | Termine lesen (gehört zu Stufe 1, braucht aber Vollzugriff) | Kalender voll | `NSCalendarsFullAccessUsageDescription` |
| `reminder_add {title, due?, list?}` | Erinnerung anlegen | Erinnerungen voll (iOS 17 kennt kein „nur Schreiben“ für Erinnerungen) | `NSRemindersFullAccessUsageDescription` |
| `contacts_find {query}` | Name, Telefon, Mail eines Kontakts | Kontakte | `NSContactsUsageDescription` |
| `files_put {folder, path, upload}` | Datei vom PC in einen freigegebenen Ordner legen | Ordnerfreigabe mit Schreibrecht | keine |
| `photos_save {upload}` | Bild in die Mediathek sichern | Fotos nur hinzufügen | `NSPhotoLibraryAddUsageDescription` |
| `clipboard_set {text}` | Text in die Zwischenablage | keine | keine |
| `shortcut_run` mit „verändert etwas“ | wie Stufe 2 | wie Stufe 2 | wie Stufe 2 |

Nicht im Katalog, auch später nicht: Löschen von Fotos, Kontakten, Terminen und Dateien. Wenn das je nötig wird, als
eigener Eintrag mit eigener Freigabe.

## Protokollerweiterung (Gateway und App)

Baut auf dem vorhandenen Muster `send_request` / `send_result` auf (PROTOCOL.md „Desktop → phone“).

- Persistiertes Ereignis `phone_command {"request_id", "command", "args", "requested_by", "reason", "needs_confirm",
  "expires_at"}`. `needs_confirm` setzt das Gateway nach Katalog, nicht der Agent.
- RPC `phone_command_result {"request_id", "ok", "result"?, "upload"?, "error"?}`. Fehlertexte: `denied`
  (Martin hat abgelehnt), `not_allowed` (Bereich nicht freigegeben), `not_in_foreground`, `unsupported`,
  `killswitch`, `expired`.
- Persistiertes Ereignis `phone_command_resolved {"request_id", "ok"}` (zweites Gerät, Liste in der App).
- RPC `phone_command {"command", "args", "reason", "wait_s"}` für Agenten (wie `phone_request`), RPC
  `phone_command_status {"request_id"}`.
- RPC `phone_caps` (App → Gateway beim Verbinden): welche Bereiche freigegeben sind, welche Ordner, welche Kurzbefehle,
  Not-Aus an/aus. Das Gateway lehnt Befehle für nicht freigegebene Bereiche sofort ab, statt sie liegen zu lassen.
- Ablauf im Gateway: Tabelle `phone_commands` (wie `requests`), Frist 10 min für Lesen, 24 h für Schreiben,
  Protokoll als JSONL unter `~/.local/share/notifyd/telefonzugriff/JJJJ-MM-TT.jsonl` (Befehl, Wer, Ergebnis ohne
  Inhalte, Dauer).
- Dateien und Fotos gehen über den vorhandenen Upload-Weg (`upload_*`), das Ergebnis enthält nur den Pfad am PC.

## Gateway-Werkzeug für Agenten

- CLI: `notifyd phone do <befehl> [--arg schlüssel=wert …] --reason "…" [--wait 120] [--json]`, dazu
  `notifyd phone do --list` (Katalog mit Stufe, Bestätigung ja/nein, Freigabe ja/nein laut letztem `phone_caps`).
- MCP-Werkzeug `phone_do(command, args, reason)` im vorhandenen MCP-Server (Jarvis und Team), gleiche Regeln.
- Antwort immer JSON: `{"status": "done"|"pending"|"denied"|"failed", "result"?, "file"?, "phone"?}`; bei `pending`
  wie heute der Text, seit wann das Handy offline ist.
- Inhalte aus dem Handy (Dateinamen, Kontakte, Termintexte) gelten als nicht vertrauenswürdig: Agenten folgen keinen
  Anweisungen darin (wie bei `phone_inbox`).

## Sicherheitsmodell

1. **Fester Katalog:** nur die Befehle oben, Felder werden im Gateway und in der App geprüft. Unbekannte Befehle lehnt
   die App ab, auch wenn das Gateway sie schicken würde.
2. **Lesen nach einmaliger Freigabe je Bereich:** Einstellungen „Telefonzugriff“ mit einem Schalter je Bereich
   (Geräteinfos, Ordner, Fotos, Kalender, Kontakte, Zwischenablage, Kurzbefehle). Aus = sofort `not_allowed`.
   Die iOS-Berechtigung allein reicht nicht; beides muss an sein.
3. **Schreiben, Senden, Kurzbefehle mit „verändert etwas“: immer Bestätigung am Handy.** Karte im Freigaben-Streifen
   (wie `send_request`) mit Befehl, Inhalt im Klartext, wer fragt und warum; „Ausführen“ verlangt entsperrtes Gerät
   (Face ID, wenn die App-Sperre an ist). Keine Sammelfreigabe.
4. **Protokoll in App und Gateway:** jede Anfrage mit Zeit, Agent, Befehl, Ergebnis; in der App unter
   „Telefonzugriff → Verlauf“ (30 Tage), im Gateway als JSONL. Inhalte (Text, Bilder) nicht im Protokoll.
5. **Not-Aus:** ein Schalter ganz oben in „Telefonzugriff“ und als Aktion im Freigaben-Streifen. An = alle Befehle
   `killswitch`, offene Anfragen werden abgelehnt. Das Gateway erfährt es über `phone_caps`.
6. **Grenzen:** höchstens 30 Lesebefehle je Stunde und Agent, Dateien höchstens 100 MB, Fotos höchstens 20 je Befehl.
   Darüber fragt die App nach.

## Was unter SideStore (kostenloses Konto) nicht geht

| Wunsch | Unter SideStore | Ausweg |
|---|---|---|
| Handy per Push aufwecken, wenn ein Agent etwas will | nein (APNs braucht bezahltes Konto) | Befehle warten; Hinweis über die bestehende Verbindung, Hintergrundabruf |
| iCloud-Container, CloudKit | nein | nicht nötig, iCloud Drive geht über die Dateien-App |
| App Groups und Erweiterungen (Share Extension, Widget mit Daten) | eingeschränkt, SideStore richtet App Groups teils ein, unsicher | nicht einplanen |
| HealthKit | mit kostenlosem Konto grundsätzlich möglich, unter SideStore ungeprüft | nicht Teil von v0.4.0 |
| Siri-Entitlement (SiriKit) | nein | App Intents (laufen ohne Entitlement, schon im Einsatz für „Jarvis in Relay“) |
| Fotos, Dateien, Kontakte, Kalender, Erinnerungen, Standort, Zwischenablage | ja (nur Datenschutzabfragen, keine Entitlements) | |
| Kurzbefehle per URL-Schema | ja | |

Dazu die bekannten Grenzen: Signatur läuft nach 7 Tagen ab (SideStore erneuert), höchstens 3 eigene Apps. Die Einträge
in „unsicher“ habe ich nicht am Gerät geprüft.

## Aufwand je Stufe (geschätzt, Nachtbau-Einheiten zu je etwa 3 Einträgen)

| Stufe | Inhalt | Aufwand |
|---|---|---|
| 1 | Katalog, Gateway-Tabelle und Werkzeug, Einstellungen mit Bereichsschaltern und Not-Aus, Verlauf, `device_info`, Ordnerfreigabe mit `files_list`/`files_get`, `photos_recent`/`photos_get`, `clipboard_get` | 2 Nachtbauten (Gateway mit Tests, App mit RelayCore-Logik und UI-Tests im Mock) |
| 2 | URL-Schema, `shortcut_run` mit Rücksprung, Freigabeliste der Kurzbefehle, App Intent „Ergebnis an Relay“ | 1 Nachtbau, dazu ein Test am Gerät durch Martin (x-callback ist im Simulator nur teilweise prüfbar) |
| 3 | Bestätigungskarten, Kalender, Erinnerungen, Kontakte, `files_put`, `photos_save`, `clipboard_set` | 1 bis 2 Nachtbauten |

## Entscheidungen (Martin, 7. November 2026)

Alle fünf Fragen unten mit Ja beantwortet: „Lösung bei Sönke“ entfällt; Stufe 1 mit Geräteinfos, Ordnern und Fotos,
ohne Kalender und Kontakte; Google Drive nur über die Ordnerfreigabe der Dateien-App, keine Google-API und keine
Zugangsdaten in Relay; Lesen im einmal freigegebenen Bereich ohne Einzelbestätigung, aber mit Protokoll, Schreiben immer
mit Bestätigung; das Gateway erinnert einmal je Befehl, Relay zu öffnen, wenn ein Befehl länger als 5 Minuten wartet,
nicht in den Ruhezeiten.

## Umsetzung Stufe 1 (Version 0.3.11)

- **App:** Einstellungen → „Telefonzugriff für Agenten“: Not-Aus ganz oben, Verlauf (30 Tage, ohne Inhalte), je ein
  Schalter für Geräteinfos, Ordner, Fotos und Zwischenablage (alle anfangs aus), Ordnerfreigabe per Auswahldialog mit
  kurzem Namen (Umbenennen und Entfernen über langes Drücken). Befehle: `device_info`, `files_list`, `files_get`,
  `photos_recent`, `photos_get`, `clipboard_get` (nur bei geöffneter App; kommt der Befehl im Hintergrund, wartet er,
  bis Relay vorn ist). Prüfung in RelayCore (`PhonePolicy`, `PhoneCatalog`, `PhonePaths`, `FolderNames`, `PhoneLog`).
- **Gateway** (`~/relay`, `gateway/src/notifyd/phonecmd.py`): RPCs `phone_command`, `phone_command_status`,
  `phone_command_catalog`, `phone_command_pending`, `phone_command_result`, `phone_caps`; Ereignisse `phone_command`
  und `phone_command_resolved`; Protokoll unter `~/.local/share/notifyd/telefonzugriff/`; Erinnerung nach 5 Minuten.
- **Agenten:** `notifyd phone do <befehl> [--arg schlüssel=wert …] --reason "…" [--wait 120]`, `notifyd phone do --list`,
  MCP-Werkzeug `phone_do`. Beispiel: `notifyd phone do files_list --arg folder=scans --reason "Rechnung suchen"`.
- **Abweichungen vom Konzept:** Dateien höchstens 50 MB (die vorhandene Upload-Grenze des Gateways), nicht 100 MB. Der
  Not-Aus sitzt nur in den Einstellungen, nicht zusätzlich im Freigaben-Streifen. Über 30 Anfragen je Stunde und
  Agent lehnen Gateway und App ab (`rate_limit`), statt nachzufragen. Fotos tragen den Ort auf drei Nachkommastellen
  gerundet (etwa 100 m).

## Offene Entscheidungen für Martin (beantwortet, siehe oben)

1. **Was meinte „Lösung bei Sönke“ im Diktat?** Empfehlung: kurz sagen, ob das ein Vorbild (eine App oder Lösung bei
   jemandem) ist; bis dahin baut Stufe 1 ohne Bezug darauf.
2. **Stufe 1 so freigeben?** Empfehlung: ja, mit Geräteinfos, Ordnern und Fotos, ohne Kalender und Kontakte.
3. **Google Drive über die Dateien-App (Ordnerfreigabe) statt Google-API?** Empfehlung: ja. Keine Zugangsdaten in
   Relay, kein fremder Dienst, funktioniert für jeden Anbieter in der Dateien-App.
4. **Bestätigung auch für Lesen von Fotos und Dateien?** Empfehlung: nein, nur einmalige Freigabe je Bereich plus
   Protokoll; sonst wird es lästig. Schreiben immer mit Bestätigung.
5. **Wartende Befehle ohne Push:** Darf das Gateway Martin per Hinweis bitten, Relay zu öffnen, wenn ein Befehl
   länger als 5 Minuten wartet? Empfehlung: ja, höchstens einmal je Befehl und nicht in den Ruhezeiten.
