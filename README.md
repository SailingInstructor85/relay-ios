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
  (Leisten und Tastatur weg, der Verlauf füllt den Bildschirm). Die Tastatur schließt ein Knopf in der Leiste über ihr,
  ein Tipp in den Verlauf oder Wischen nach unten.
- **Antwortkarten** für Fragen, Auswahllisten (`/model`, Berechtigungsabfragen, Plan-Freigabe) und Panels (`/usage`,
  `/status`), mit `expect_menu`, damit eine veraltete Karte keinen neuen Dialog beantwortet
- **Live-Bildschirm** (tmux-Aufnahme) mit Tastenleiste: Esc, Enter, Pfeiltasten, Tab, Ctrl-C, Ziffern
- **Neue Sitzung:** Konto wählen, Ordner aus den zuletzt benutzten, per Suche oder durch Blättern, erste Nachricht
- **Anhänge:** Fotos und Dateien hochladen, der Pfad landet in der Nachricht
- **Nutzung & Limits** pro Konto, **RAM-Monitor** mit Schließen und Wiederöffnen
- **Jarvis per Sprache:** Mikrofon antippen und sprechen. Die Erkennung läuft auf dem iPhone und nutzt das Vokabular
  des Gateways (`voice_vocab`). Die Antwort wird Satz für Satz vorgelesen. Im Gesprächsmodus hört Jarvis danach
  wieder zu. Der Kurzbefehl „Jarvis in Relay“ funktioniert per Siri oder über die Aktionstaste.
- **Mitteilungen** bei „fertig“ und „wartet“. Direkt aus der Mitteilung antworten, „Erledigt“ setzen oder die
  Sitzung stummschalten. Bis zu drei verpasste Ereignisse kommen einzeln, mehr als Zusammenfassung.
- **Hintergrundaktualisierung:** Ist die App zu, verbindet sie sich ab und zu kurz und meldet Verpasstes. iOS bestimmt
  den Zeitpunkt, meist alle 15 bis 60 Minuten.
- **Suche im Verlauf** einer Sitzung, ein Treffer springt an die Stelle im Chat
- **Sperre mit Face ID** (Einstellungen → Sicherheit)

Noch nicht enthalten, weil iOS es nicht zulässt oder weil es später kommt: ein dauerhaft lauschendes Wake-Word
„Hey Jarvis“ (stattdessen Siri oder die Aktionstaste), die Telefon-Bridge (SMS, Health, fremde Mitteilungen), das
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

## Verbindung einrichten

1. App öffnen. Sie zeigt den Befehl `notifyd setup key "ssh-ed25519 … relay-iphone"`.
2. Den Befehl kopieren und auf dem Desktop ausführen (mit vollem Pfad, z. B.
   `~/relay/gateway/.venv/bin/notifyd setup key "…"`). Er trägt den Schlüssel eingeschränkt in `authorized_keys`
   ein: `restrict,pty,command="…/notifyd ssh-entry"`.
3. Auf dem Desktop muss `sshd` laufen (`sudo systemctl enable --now sshd`).
4. In der App Host (LAN-IP oder WireGuard-Adresse), Port und Benutzer eintragen und dann „Verbinden“ tippen.
   Der Host-Schlüssel wird beim ersten Mal gepinnt, ein geänderter Schlüssel wird abgelehnt.

## Später in den App Store

Nötig sind ein Apple-Developer-Konto (99 €/Jahr) und ein Mac oder ein CI-Signing-Setup
(App-Store-Connect-API-Key, Distribution-Zertifikat und Provisioning-Profile als GitHub-Secrets). Dazu kommen eine
Datenschutzerklärung (die App sammelt nichts, alles läuft über die eigene SSH-Verbindung) und die Prüfung durch Apple.
Der Workflow lässt sich dann um `xcodebuild archive` / `-exportArchive` und den Upload zu TestFlight erweitern.

## Lizenz

MIT wie das Original-Repo, siehe `LICENSE` und `NOTICE`.
