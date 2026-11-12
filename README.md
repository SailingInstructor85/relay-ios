# Relay für iPhone

Native SwiftUI-App für [Relay](https://github.com/chart21/relay): Sie verbindet das iPhone per SSH mit dem
Relay-Gateway (`notifyd`) auf dem Linux-Desktop und bildet den Kern der Android-App nach. Getestet ist sie für ein
iPhone 16 Pro (iOS 17 oder neuer).

## Funktionen (Version 0.2)

- **SSH wie bei Android:** eigener Ed25519-Schlüssel im iOS-Schlüsselbund, Host-Key-Pinning beim ersten Verbinden (TOFU),
  nur der `serve`-Kanal von `notifyd ssh-entry`, kein Shell-Zugang
- **Sitzungsliste** über alle Konten: zuerst „Wartet auf dich“, dann „Arbeitet“, „Bereit“ und „Beendet“; dazu Suche,
  Anheften, „Erledigt“ (Wischen nach rechts) und Schließen (Wischen nach links)
- **Chat pro Sitzung:** Transkript mit Nachladen älterer Nachrichten, Live-Anhänge (`watch`), eingeklappte
  Werkzeugaufrufe, Codeblöcke, Statuszeile während die Sitzung arbeitet. Lesemodus über den Knopf oben rechts
  (Leisten und Tastatur weg, der Verlauf füllt den Bildschirm). Die Tastatur schließt ein Knopf rechts in der Schnellantwort-Zeile über dem Eingabefeld,
  ein Tipp in den Verlauf oder Wischen nach unten.
- **Antwortkarten** für Fragen, Auswahllisten (`/model`, Berechtigungsabfragen, Plan-Freigabe) und Panels (`/usage`,
  `/status`), mit `expect_menu`, damit eine veraltete Karte keinen neuen Dialog beantwortet
- **Live-Bildschirm** (tmux-Aufnahme) mit Tastenleiste: Esc, Enter, Pfeiltasten, Tab, Ctrl-C, Ziffern
- **Neue Sitzung:** Konto wählen, Ordner aus den zuletzt benutzten, per Suche oder durch Blättern, erste Nachricht
- **Anhänge:** Fotos und Dateien hochladen, der Pfad landet in der Nachricht. Aus der Mediathek gehen mehrere Fotos
  und Videos auf einmal: Sie stehen erst als Vorschau über der Eingabe und gehen mit „N Fotos hochladen“ (oder Senden)
  gemeinsam hoch.
- **Nutzung & Limits** pro Konto, **RAM-Monitor** mit Schließen und Wiederöffnen
- **Jarvis per Sprache:** Jarvis ist der eingebaute Sprachassistent von Relay für Fragen an das Gateway (kein Agent
  von Christopher). Mikrofon antippen und sprechen. Nach einer kurzen Pause fragt Jarvis von selbst; der rote Knopf
  beendet die Aufnahme und legt den Text ins Schreibfeld, Senden während der Aufnahme schickt ihn gleich ab. Die
  Erkennung läuft auf dem iPhone und nutzt das Vokabular des Gateways (`voice_vocab`). Die Antwort wird Satz für Satz
  vorgelesen. Im Gesprächsmodus hört Jarvis danach wieder zu. Der Kurzbefehl „Jarvis in Relay“ funktioniert per Siri
  oder über die Aktionstaste.
- **Alle Sitzungen beenden** (Menü der Sitzungsliste): Jede gewählte Sitzung schreibt ihren Eintrag ins Agenten-Log
  der Daily Note und ihre Übergabe, dann beendet das Gateway sie. Sitzungen mit offener Auswahl oder Freigabe am PC
  bleiben mit Grund offen. Das Gateway schickt Nachrichten mit getrenntem Enter und prüft, ob das Eingabefeld am PC
  danach leer ist; bleibt Text stehen, meldet die App das, statt still zu scheitern.
- **Mitteilungen** bei „fertig“ und „wartet“. Direkt aus der Mitteilung antworten, „Erledigt“ setzen oder die
  Sitzung stummschalten. Bis zu drei verpasste Ereignisse kommen einzeln, mehr als Zusammenfassung.
- **Hintergrundaktualisierung:** Ist die App zu, verbindet sie sich ab und zu kurz und meldet Verpasstes. iOS bestimmt
  den Zeitpunkt, meist alle 15 bis 60 Minuten.
- **Suche im Verlauf** einer Sitzung, ein Treffer springt an die Stelle im Chat
- **Vorlesen auf Knopfdruck:** Lautsprecher-Symbol unter jeder Agentenantwort, „Letzte Antwort vorlesen“ im
  Sitzungsmenü, Leiste mit Pause und Stopp über der Eingabe. „Frage vorlesen“ liest nur die Frage mit Optionen und
  Empfehlung vor (Langdruck-Menü, Sitzungsmenü, Fragekarten, Rückfragen unter „Hinweise“). Codeblöcke werden
  übersprungen, Pfade beim Dateinamen genannt, Links als „Link“.
- **Sprachmodus für die Autofahrt** (Hinweise → „Sprachmodus“ oder Kurzbefehl „Sprachmodus in Relay“): liest offene
  Rückfragen vor (nur Frage und Empfehlung), du antwortest mit „ja“, „nein“ oder in eigenen Worten, hörst die Antwort
  zur Kontrolle und gibst sie mit „senden“ frei („nochmal“ oder ein neuer Satz korrigiert). Neue Rückfragen liest er
  sofort vor. Dazu ein Freihand-Gespräch mit einer laufenden Sitzung: sprechen, kontrollieren, senden, die Antwort
  gekürzt hören. Große Knöpfe für alles, Bildschirm bleibt an, Ton über Bluetooth oder CarPlay. Details:
  `docs/sprachmodus.md`.
- **Routinen** (Menü → „Routinen“): Routinen des Gateways mit Zeitplan, letztem Lauf, Schalter, „Jetzt ausführen“
  und den systemd-Timern des PCs; „Neue Routine“ in Worten an den Chef-Agenten. Braucht einen `team:`-Block in der
  Gateway-Konfiguration, sonst zeigt die App „Routinen im Gateway nicht eingerichtet“ (Einrichtung: `docs/routinen.md`).
- **Handy und PC in derselben Sitzung:** Beide tippen abwechselnd in eine Sitzung, die in einer Agenten-tmux-Sitzung
  läuft (so startet die App jede Sitzung). Ein Monitor-Symbol im Chat-Kopf und in der Liste zeigt „Am PC offen“, wenn
  gerade ein Terminal am PC die Sitzung zeigt (nur Anzeige). Läuft eine Sitzung am PC als nacktes `claude` ohne tmux,
  liest das Handy nur mit: Nachrichten warten im Postausgang, über der Eingabe steht ein Hinweis mit dem Befehl, der
  die Sitzung am PC in tmux neu öffnet (`claude --resume <id>`); danach gehen die wartenden Nachrichten von selbst hinaus. Den Knopf „Am PC beenden und hier fortsetzen“ gibt es
  seit 0.3.16 nicht mehr. Damit der Fall gar nicht eintritt, `claude` am PC per Wrapper in tmux starten: `docs/pc-tmux.md`.
- **Telefonzugriff für Agenten** (Einstellungen → „Telefonzugriff für Agenten“, Stufe 1, nur Lesen): Agenten fragen
  über das Gateway Geräteinfos, Dateien aus freigegebenen Ordnern der Dateien-App (auch Google Drive), die neuesten
  Fotos oder die Zwischenablage ab. Jeder Bereich hat einen Schalter (anfangs aus), Lesen läuft dann ohne Rückfrage,
  jede Anfrage steht im Verlauf. Der Not-Aus lehnt alles ab. Am PC: `notifyd phone do --list`. Ist Relay zu, wartet der
  Befehl; nach 5 Minuten kommt einmal ein Hinweis, Relay zu öffnen. Details: `docs/telefonzugriff.md`.
- **Verbindung klappt nicht?** Über der Sitzungsliste steht der Grund in Klartext mit der passenden Hilfe statt der
  rohen Fehlermeldung: „Kein Netz“ (Knopf zu den iOS-Einstellungen), „Keine Verbindung. Tailscale ist vermutlich aus.“
  (Knöpfe „Tailscale verbinden“ und „Tailscale öffnen“), „Kein Weg zum PC“ (nur die Heimnetz-Adresse eingetragen und
  unterwegs), „PC schläft“, „PC nicht erreichbar“ (aus, Ruhezustand oder ohne Netz), „PC nimmt keine Verbindung an“
  (SSH-Dienst), „PC lehnt dieses iPhone ab“ (Schlüssel-Befehl zum Kopieren), „Host-Schlüssel passt nicht“ (neuen
  Schlüssel nach Rückfrage übernehmen) und „Gateway läuft nicht“ (Startbefehl für notifyd zum Kopieren). Jeder Fall
  nennt, was am PC oder am iPhone zu tun ist. Trennt die App selbst (zurück im Vordergrund, „Erneut“), erscheint kein
  Fehler mehr.
- **Tailscale aus?** Hat iOS Tailscale im Hintergrund beendet, startet der Knopf „Tailscale verbinden“ den
  Kurzbefehl „Tailscale verbinden“ (Tailscale-Aktion „Connect“, ab Tailscale 1.36), kehrt zu Relay zurück und verbindet
  neu. Der Hinweis erscheint nur, wenn eine Adresse des PCs eine Tailscale-Adresse ist und das iPhone gerade keine hat.
  Einrichtung: Einstellungen → Status → „Tailscale verbinden“ (Name des Kurzbefehls und Anleitung).
- **Vault-Chat ohne Verbindung:** Ohne Verbindung steht oben in der Liste „Nachricht an Vault-Agent“. Text, Diktat und
  Anhänge warten auf dem iPhone („wartet auf Verbindung“). Steht die Verbindung wieder, startet Relay einen Agenten im
  Vault-Ordner (Einstellungen → Ablage) mit allen wartenden Nachrichten in der richtigen Reihenfolge; spätere gehen in
  dieselbe Sitzung, solange sie läuft. Nichts geht doppelt raus.
- **Verpasste Antworten und wartende Nachrichten (seit 0.3.16):** Bricht die Verbindung ab, während ein Chat offen ist
  (iOS trennt sie im Hintergrund nach kurzer Zeit), lädt der Chat nach dem Wiederverbinden den Verlauf nach und liest
  wieder live mit. Antworten, die in der Zwischenzeit kamen, erscheinen ohne Schließen und Öffnen. Arbeitet beim
  Wechsel in den Hintergrund noch eine Sitzung, hält Relay die Verbindung bis zu 25 Sekunden, damit eine kurze Antwort
  noch als Mitteilung „Fertig“ ankommt. Lehnt der PC eine Nachricht ab, weil die Sitzung gerade arbeitet oder am PC
  ohne tmux läuft, wartet sie im Postausgang („Wartet: … Geht von selbst hinaus“) und geht innerhalb einer Stunde von
  selbst hinaus, sobald die Sitzung frei ist. In der Sitzungsliste steht dann „1 Nachricht wartet auf die Sitzung“
  oder „1 Nachricht nicht gesendet“.
- **Musik pausiert beim Sprechen:** Diktat, Jarvis, Sprachmodus und Vorlesen unterbrechen Spotify und andere Apps,
  statt sie nur leiser zu stellen. Beim Diktat im Chat läuft die Musik weiter, sobald die Aufnahme endet (auch wenn
  der Text noch im Feld steht), bei Jarvis und im Sprachmodus nach der vorgelesenen Antwort. Gibt iOS das Audio nicht
  sofort zurück, versucht die App es noch dreimal. Übernahme, Freigabe und Unterbrechungen stehen im Nutzungsprotokoll
  (Ansicht „audio“ mit dem Audioweg). Braucht mindestens Version 0.3.12 auf dem Handy.
- **Bildschirm bleibt an:** Im Chat und im Live-Bildschirm bis 60 s nach der letzten Berührung, während einer
  Mikrofon-Aufnahme (Diktat, Jarvis) höchstens 10 Minuten ab ihrem Start, im Sprachmodus durchgehend. Danach oder beim
  Ende der Aufnahme gilt wieder die normale automatische Sperre.
- **Sperre mit Face ID** (Einstellungen → Sicherheit)
- **Nutzungsprotokoll und „Fehler melden“** (Einstellungen → Nutzungsprotokoll, standardmäßig an): Die App zeichnet
  auf, was du tust (Ansicht, Aktion, Sitzung, Verbindung, Fehler), ohne Inhalte, von Text, Diktat und Fotos nur Art
  und Länge. Das Protokoll geht nur ans eigene Gateway und bleibt 30 Tage. „Fehler melden“ schickt eine kurze
  Beschreibung mit den letzten 10 Minuten; den Text dieser Minuten nur mit dem Haken „Inhalte mitsenden“. Agenten lesen
  es am PC mit `notifyd phone usage --since 10:30` und `notifyd phone reports --show`. Braucht ein aktuelles Gateway.

Noch nicht enthalten, weil iOS es nicht zulässt oder weil es später kommt: ein dauerhaft lauschendes Wake-Word
„Hey Jarvis“ (stattdessen Siri oder die Aktionstaste), die Telefon-Bridge (SMS, Health, fremde Mitteilungen; Wege dazu in `docs/benachrichtigungen-fremder-apps.md`), das
Teilen-Menü und ein Homescreen-Widget (beide brauchen eigene App-IDs, siehe App-Store-Abschnitt) sowie sofortige
Mitteilungen bei geschlossener App. Für Letzteres bräuchte man Apple-Push über einen Server, und den will Relay bewusst
nicht.

## Aufbau

```
RelayCore/   Swift-Paket: Protokoll (PROTOCOL.md v2), SSH (Citadel/swift-nio-ssh), Modelle. Baut und testet auch unter Linux.
App/         SwiftUI-App (iOS 17+)
project.yml  XcodeGen-Projekt; .github/workflows/ios.yml baut daraus eine unsignierte IPA
```

Tests unter Linux: `cd RelayCore && swift test`. Ende-zu-Ende-Test gegen ein Gateway:
`swift run relay-smoke <host> <port> <user> <seed-datei> [rpc-methode [json]]`.

## Installation auf dem iPhone (ohne App Store)

1. **IPA bauen:** Push nach GitHub. Der Workflow „iOS build“ läuft auf einem macOS-Runner und legt
   `Relay-unsigned.ipa` als Artefakt ab. Bei einem Tag `v*` landet sie zusätzlich in einem Release.
2. **SideStore** (empfohlen, kein Mac nötig) oder **AltStore** einmalig nach deren Anleitung aufs iPhone bringen.
   Das läuft mit deiner normalen Apple-ID. SideStore braucht für die Ersteinrichtung einmal einen Rechner, danach
   nicht mehr.
3. Die IPA auf dem iPhone in SideStore öffnen („+“ → Datei). SideStore signiert sie mit deiner Apple-ID.
4. **Updates automatisch:** In SideStore unter „Quellen“ → „+“ diese Adresse eintragen:
   `https://github.com/SailingInstructor85/relay-ios/releases/latest/download/source.json`.
   Jede neue Version (Git-Tag `v*`) erscheint dann in SideStore als Update.
5. Mit einer kostenlosen Apple-ID läuft die Signatur nach **7 Tagen** ab. SideStore erneuert sie auf dem iPhone
   selbst (Refresh), dafür muss das VPN bzw. der Pairing-Mechanismus von SideStore aktiv sein.

## Versionshinweise und Dokumentation

- `CHANGELOG.md` im Repo führt alle Versionen (neueste oben, je Version „Neu“, „Geändert“, „Behoben“). Der Abschnitt der
  getaggten Version wird beim Release automatisch zum Release-Text auf GitHub (`scripts/changelog_section.py`) und zur
  Versionsbeschreibung in SideStore („Neu in dieser Version“, `scripts/make_source.py`). Fehlt der Abschnitt, steht
  dort ein kurzer Standardtext, der Build bricht nicht ab.
- `docs/` gehört zum Repo und wird je Version mitgepflegt: `docs/nachtlog.md` (was wann gebaut wurde, Entscheidungen,
  Risiken), `docs/feature-parity.md` (Abgleich mit der Android-App), `docs/rueckfragen.md`, `docs/routinen.md`,
  `docs/pc-tmux.md` (Handy und PC in derselben Sitzung, Wrapper und tmux-Einstellung für den PC), `docs/telefonzugriff.md`
  (Agenten greifen über Relay aufs iPhone zu, Stufe 1 seit 0.3.11), `docs/benachrichtigungen-fremder-apps.md` (Konzept:
  WhatsApp-Mitteilungen für Agenten), `docs/testbericht.md`. Der Release-Text verlinkt README, Nachtlog und Changelog im Stand des Tags.
- Lokal prüfen (nur Python nötig): `python3 scripts/changelog_section.py 0.3.5 --release --repo <owner/repo> --tag v0.3.5`
  und `python3 scripts/make_source.py <ipa> 0.3.5 1 <owner/repo> v0.3.5 source.json CHANGELOG.md`.

## Verbindung einrichten

1. App öffnen. Sie zeigt den Befehl `notifyd setup key "ssh-ed25519 … relay-iphone"`.
2. Den Befehl kopieren und auf dem Desktop ausführen (mit vollem Pfad, z. B.
   `~/relay/gateway/.venv/bin/notifyd setup key "…"`). Er trägt den Schlüssel eingeschränkt in `authorized_keys`
   ein: `restrict,pty,command="…/notifyd ssh-entry"`.
3. Auf dem Desktop muss `sshd` laufen (`sudo systemctl enable --now sshd`).
4. In der App Host (LAN-IP oder WireGuard-Adresse), Port und Benutzer eintragen und dann „Verbinden“ tippen.
   Der Host-Schlüssel wird beim ersten Mal gepinnt, ein geänderter Schlüssel wird abgelehnt.
5. Mit Tailscale: In der Kurzbefehle-App einen Kurzbefehl „Tailscale verbinden“ mit der Tailscale-Aktion „Connect“
   anlegen (Einstellungen → Status → „Tailscale verbinden“ zeigt die Schritte). Dann reicht ein Tipp auf den Knopf im
   Hinweis, wenn iOS Tailscale beendet hat.

## Später in den App Store

Nötig sind ein Apple-Developer-Konto (99 €/Jahr) und ein Mac oder ein CI-Signing-Setup
(App-Store-Connect-API-Key, Distribution-Zertifikat und Provisioning-Profile als GitHub-Secrets). Dazu kommen eine
Datenschutzerklärung (die App sammelt nichts, alles läuft über die eigene SSH-Verbindung) und die Prüfung durch Apple.
Der Workflow lässt sich dann um `xcodebuild archive` / `-exportArchive` und den Upload zu TestFlight erweitern.

## Lizenz

MIT wie das Original-Repo, siehe `LICENSE` und `NOTICE`.
