# Changelog

Versionen der iPhone-App Relay, neueste oben. Aus dem Abschnitt der getaggten Version entstehen der Release-Text auf GitHub und die Versionsbeschreibung in SideStore („Neu in dieser Version“). Je Version: **Neu**, **Geändert**, **Behoben**.

## 0.3.6 (2026-11-07)

**Neu**
- Vorlesen auf Knopfdruck: Unter jeder Agentenantwort ein kleines Lautsprecher-Symbol, im Sitzungsmenü „Letzte Antwort vorlesen“. Während des Vorlesens erscheint über der Eingabe eine Leiste mit Pause, Weiter und Stopp. Die Wiedergabe läuft über den aktuellen Audioausgang, also auch über Bluetooth-Kopfhörer, mit der in den Einstellungen gewählten Stimme. Codeblöcke werden übersprungen („Codeblock ausgelassen“), Pfade nur beim Dateinamen genannt, Links als „Link“, Tabellen Zelle für Zelle.
- Nur die Frage vorlesen: Enthält eine Antwort eine Rückfrage oder Entscheidung, liest „Frage vorlesen“ (Langdruck-Menü der Nachricht, Sitzungsmenü) nur die Frage mit Optionen und Empfehlung vor, nicht den Rest. Fragekarten der Sitzung und Rückfragen von Agenten unter „Hinweise“ haben den Knopf ebenfalls.
- Routinen: Menü der Sitzungsliste → „Routinen“ zeigt die Routinen des Gateways mit Titel, Beschreibung, Zeitplan, nächstem und letztem Lauf, Schalter an/aus, Detailansicht mit „Jetzt ausführen“ und Link zur Sitzung des Handoffs, dazu die systemd-Timer des PCs (nur Anzeige). „Neue Routine…“ geht in Worten an den Chef-Agenten, der den Eintrag schreibt und zurückfragt. Routinen erscheinen auch in der App-Suche. Ist im Gateway kein Team eingerichtet, sagt die App das („Routinen im Gateway nicht eingerichtet“); die Einrichtung ist in der Dokumentation beschrieben.
- Versionshinweise im Repo: `CHANGELOG.md` führt alle Versionen. Der Abschnitt der getaggten Version wird automatisch zum Release-Text auf GitHub und zur Versionsbeschreibung in SideStore („Neu in dieser Version“), mit Links auf README, Nachtlog und Changelog.

**Geändert**
- Hauptmenü der Sitzungsliste: „Nutzung & Limits“, „RAM-Monitor“, „Was war los“ und „Token-Verbrauch“ stehen jetzt im Untermenü „Übersichten“, damit das Menü mit „Routinen“ auf den Bildschirm passt.
- Vorlesen eines Hinweises (und „Frage vorlesen“ bei Rückfragen) sitzt im Lautsprecher-Knopf oben rechts, nicht mehr als Zeile im Hinweis.

## 0.3.5 (2026-11-07)

**Neu**
- Lesemodus im Chat: Der Knopf oben rechts (Pfeile nach außen) blendet Navigationsleiste, Eingabezeile und Tastatur aus, der Verlauf nutzt den ganzen Bildschirm. Neue Nachrichten laufen weiter ein, der Bildschirm bleibt wie beim Zuschauen an. Der kleine Knopf oben rechts bringt die normale Ansicht zurück.
- Tastatur im Chat schließen: Ein Knopf in der Leiste über der Tastatur, ein Tipp in den Verlauf oder Wischen nach unten schließt sie. Getippter Text und ein laufendes Diktat bleiben erhalten.

**Geändert**
- Sitzungsübergabe Handy/PC entfernt: kein „Sitzung übernehmen“, keine Rückfrage „Sitzung vom PC übernehmen?“ vor dem Senden, keine Tags „Am Handy“ und „Am PC“. Handy und PC tippen wieder wie bis 0.3.3 abwechselnd in dieselbe Sitzung. Im Gateway sind Schreibschutz, rote Statuszeile und Strg-b H weg. „Alle Sitzungen beenden“ und das Senden in Sitzungen am PC ohne tmux bleiben.

Hinweis: Damit der Rückbau auch im Gateway greift, muss notifyd einmal neu gestartet werden. Die App läuft auch mit dem älteren Gateway.

## 0.3.4 (2026-11-06)

Braucht ein aktuelles Gateway (notifyd nach dem Update neu starten).

**Neu**
- Sitzungsübergabe Handy/PC: „Sitzung übernehmen“ im Chat macht den PC schreibgeschützt (rote Statuszeile, Strg-b H holt sie zurück), Tag „Am Handy“ oder „Am PC“ in der Liste. Vor dem Senden in eine Sitzung, die ein Terminal am PC gerade zeigt oder die der PC hält, fragt die App „Sitzung vom PC übernehmen?“ mit „Übernehmen und senden“, „Nur senden“ und „Abbrechen“. Nichts wird automatisch übernommen. (In 0.3.5 wieder entfernt.)
- Alle Sitzungen beenden: Menüpunkt in der Sitzungsliste. Blatt mit allen offenen Sitzungen (Abwahl je Sitzung), Bestätigung mit Anzahl, dann je Sitzung Abschlussnachricht, Übergabenotiz des Agenten abwarten, beenden. Fortschritt je Sitzung und Zusammenfassung mit den Pfaden der Übergaben. Rückfragen lassen die Sitzung offen, nach 10 Minuten gilt „nicht sauber beendet“.

**Behoben**
- Nachricht vom Handy in eine Sitzung, die am PC in einem Terminal ohne tmux läuft: Die Nachricht geht nicht mehr verloren, sondern bleibt im Postausgang, und die App fragt „Am PC beenden und hier fortsetzen?“. Nach Ja beendet das Gateway die Sitzung am PC und setzt sie in tmux mit genau dieser Nachricht fort.

## 0.3.3 (2026-11-06)

**Neu**
- Rückfragen von Agenten kommen als Push aufs iPhone: Mitteilung mit Agent, Nummer und Frage, Aktionen „Antworten“ und „Ja (Empfehlung)“. Ein Tipp öffnet die Rückfrage unter „Hinweise“ mit Antwortfeld. Die Antwort geht über den Eingang des Gateways zurück. Meldungen der Agenten werden nur gezeigt.

**Behoben**
- Diktat: Der Anfang einer Sprachnachricht geht nicht mehr verloren, wenn die iOS-Erkennung nach einer Sprechpause intern neu ansetzt. Eine Teil-Hypothese kann nicht mehr die vollständige verdrängen.
- Senden während des Diktats blockiert den Chat nicht mehr: Kommt das Diktat nicht zurück, wird der Knopf nach 25 s mit dem Feldinhalt freigegeben. Doppeltipp auf das Mikrofon lässt kein Diktat mehr hängen.
- Eine Nachricht geht nie still verloren: Lehnt das Gateway ab, weil die Sitzung arbeitet, bleibt sie als abgelehnte Zeile im Postausgang (Trotzdem senden, Bearbeiten, Verwerfen); ohne Sitzung oder bei leerem Diktat sagt die App, warum nichts gesendet wurde.
- „Wiederholen“ und „Trotzdem senden“ im Postausgang funktionieren jetzt.

## 0.3.2 (2026-11-06)

Enthält auch die Punkte von 0.3.1, die nie gebaut wurde.

**Neu**
- Bildschirm bleibt an, solange ein Chat oder der Live-Bildschirm offen ist und innerhalb der letzten 60 s berührt wurde; danach und beim Verlassen gilt die normale Sperrzeit.
- Diktat: „Senden“ bleibt während des Diktats aktiv. Nach dem Tipp läuft das Mikrofon noch 2 s, dann geht alles zusammen raus.
- Zweite Adresse für den PC (etwa WLAN und Tailscale). Die App prüft kurz, welche erreichbar ist, und nimmt die. Ein Host-Schlüssel für beide. Die Einstellungen zeigen, über welche Adresse die Verbindung steht.
- Teilen: Im Blatt „In Relay öffnen“ gibt es das Ziel „Ins Vault einsortieren“. Die Datei geht an den PC, ein Agent legt sie in der Inbox des Vaults ab, liest sie und sortiert sie ein. Vault-Ordner in den Einstellungen unter „Ablage“.

## 0.3.1 (nicht veröffentlicht)

**Behoben**
- Anhängen: „Foto oder Video“ im Büroklammer-Menü öffnet die Fotoauswahl wieder (vorher passierte nichts). Fotos im HEIC-Format kommen als JPEG an.
- Diktat bricht bei längeren Aufnahmen nicht mehr ab (Ende erst nach 3 s Pause, kein Zeitlimit, Erkenner startet bei Ablauf neu).

## 0.3.0 (2026-11-05)

Funktionsabgleich mit der Android-App (Arbeitspakete 1 bis 7).

**Neu**
- Sitzungsliste mit Zustandspunkten, Leiste „N brauchen dich“, Umbenennen, Schließen mit Rückgängig, Fuzzy-Suche, Offline-Liste, Cloud-Sitzungen.
- Chat lesen: Datei-Chips mit Vorschau, Dateiansicht (Bild, PDF, Text, Markdown), tippbare Links und Pfade, Nachrichtenmenü, Markdown mit Tabellen und Codeblöcken.
- Chat schreiben: Postausgang mit Wiederholen, Schrägstrich-Chips, Schnellantworten, Modell und Effort, Fragenformular, Kamera, Diktat, Stopp.
- Mitteilungen mit Ruhezeiten, Freigeben und Ablehnen aus der Mitteilung, Hinweis-Verlauf, Freigabe-Streifen für Anfragen vom PC.
- Nutzung mit Prognose, RAM-Monitor, Einstellungen für den Jarvis-Agenten, PC ausschalten und Standby (Testlauf standardmäßig an).
- Jarvis: Stimmen- und Sprachwahl, Erkennung korrigieren, Verlauf.
- App-weite Suche inklusive Gesprächsinhalten, „In Relay öffnen“, Kurzbefehle zum Senden und Starten, Profil-Editor, Favoriten-Ordner.

**Behoben**
- 8 Fehler aus den Simulator-Tests (60 von 60 grün), darunter leere Chats durch Ereignisse alter Verbindungen.
- Der Build bei GitHub meldet Kompilierfehler jetzt als Fehler (vorher verschluckt).

## 0.2.0 (2026-11-04)

**Neu**
- Jarvis per Sprache: Mikrofon antippen, sprechen, Antwort wird Satz für Satz vorgelesen. Erkennung auf dem iPhone mit dem Vokabular des Gateways. Gesprächsmodus hört nach der Antwort wieder zu. Sprache Deutsch oder Englisch wählbar.
- Kurzbefehl „Jarvis in Relay“ für Siri und die Aktionstaste.
- Aus der Mitteilung antworten, „Erledigt“ setzen oder stummschalten.
- Sitzungen stummschalten (Wischen, Chat-Menü), Glocken-Symbol in der Liste.
- Bis zu drei verpasste Ereignisse kommen als einzelne Mitteilungen.
- Suche im Verlauf einer Sitzung, Treffer springt an die Stelle.
- Hintergrundaktualisierung: bei geschlossener App ab und zu kurz verbinden.
- Sperre mit Face ID.
- SideStore-Quelle für automatische Updates: `https://github.com/SailingInstructor85/relay-ios/releases/latest/download/source.json`

## 0.1.0 (2026-11-04)

Erste Fassung.

**Neu**
- Verbindung per SSH mit eigenem Ed25519-Schlüssel im iOS-Schlüsselbund. Host-Schlüssel wird beim ersten Verbinden gemerkt, ein geänderter wird abgelehnt.
- Einrichtung: zeigt den Befehl zum Eintragen des Schlüssels am PC, Host, Port, Benutzer.
- Sitzungsliste über alle Konten, geordnet nach „Wartet auf dich“, „Arbeitet“, „Bereit“, „Beendet“. Suche, Anheften, Erledigt und Schließen per Wischen.
- Chat je Sitzung mit Nachladen älterer Nachrichten, Codeblöcken und eingeklappten Werkzeugaufrufen.
- Antwortkarten für Fragen, Auswahllisten (z. B. `/model`, Berechtigungsabfragen) und Panels (z. B. `/usage`).
- Live-Bildschirm der Sitzung mit Tastenleiste (Esc, Enter, Pfeile, Tab, Ctrl-C, Ziffern).
- Neue Sitzung starten: Konto, Ordner (zuletzt benutzt, Suche, Blättern), erste Nachricht.
- Fotos und Dateien hochladen.
- Nutzung und Limits, RAM-Monitor, Jarvis als Text-Chat.
- Mitteilungen bei „fertig“ und „wartet“, solange die App läuft.

**Bekannte Grenzen**
- Keine Mitteilungen bei geschlossener App (bräuchte einen Push-Server).
- Kein Wake-Word, keine SMS- oder Health-Bridge wie bei Android.
- Signatur läuft mit kostenloser Apple-ID nach 7 Tagen ab, SideStore erneuert.
