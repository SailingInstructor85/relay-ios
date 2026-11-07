# Benachrichtigungen anderer Apps (WhatsApp) für Agenten

Stand: 7. November 2026, Nachtbau 19:04. Nur Konzept, kein App-Code. Wartet auf Martins Entscheidung (Fragen am Ende).
Die Aussagen zu Apple, Meta und Bibliotheken stammen aus meinem Wissen bis Mitte 2026 und sind in diesem Lauf nicht im
Netz nachgeprüft worden (der Nachtbau spricht keine Netzwerkdienste an). Was ich am Rechner geprüft habe, steht unter
„Befund am Rechner“.

## Ziel

Martin möchte, dass Agenten eingehende Nachrichten anderer Apps sehen (vor allem WhatsApp) und Anhänge daraus holen
können, bis hin zu „mit der KI über WhatsApp schreiben“.

## Was iOS grundsätzlich nicht erlaubt

- Eine iOS-App kann die Mitteilungen anderer Apps nicht lesen. Einen Notification-Listener wie bei Android
  (`NotificationListenerService`, das nutzt die Relay-Android-App als „Telefon-Bridge“) gibt es nicht, auch nicht mit
  bezahltem Entwicklerkonto.
- Relay kann WhatsApp weder bedienen noch dessen Daten lesen (Sandbox). WhatsApp bietet Kurzbefehle nur zum Senden,
  nicht zum Lesen; die Kurzbefehl-Automation „Wenn ich eine Nachricht erhalte“ gilt nur für die Nachrichten-App
  (iMessage und SMS), nicht für WhatsApp.

Es bleiben Wege außerhalb der Relay-App. Sie unterscheiden sich stark in Aufwand, Reichweite und Risiko.

## Die Wege

### (a) ANCS: der PC gibt sich als Uhr aus

**Wie es geht:** Das iPhone schickt jede Mitteilung an gekoppelte Bluetooth-Geräte, die den Apple Notification Center
Service (ANCS) nutzen (so arbeiten Fitnessuhren). Der Arch-PC kann mit BlueZ ein solches Gerät sein: Er wirbt per
Bluetooth Low Energy, das iPhone koppelt sich einmal, in den Bluetooth-Einstellungen des iPhones steht dann der
Schalter „Systemmitteilungen teilen“. Ein kleiner Dienst am PC liest Ereignisse (neu, geändert, entfernt) und holt je
Mitteilung App-Kennung (`net.whatsapp.WhatsApp`), Titel (Absender oder Gruppe), Untertitel, Text und Zeit. Er gibt sie
per `inbox_put {kind: "notification"}` ans Gateway; das gibt es schon für Android, die Agenten lesen es heute mit
`notifyd phone inbox --app whatsapp` und Jarvis mit `phone_inbox`.

**Machbarkeit:** grundsätzlich ja, mit offenen Punkten.
- Es gibt fertige Linux-Umsetzungen, zum Beispiel das Python-Projekt „ancs4linux“ (BlueZ über D-Bus). Lizenz, Pflege
  und Verhalten mit BlueZ 5.87 nicht geprüft.
- Der PC muss Bluetooth Low Energy in der Rolle „Peripherie“ können. Am PC steckt ein USB-Funkstick mit der Kennung
  `0a12:0001` (CSR, Bauart „CSR8510“). Viele billige Nachbauten dieses Sticks können Low Energy nur schlecht oder gar
  nicht als Peripherie. Ob dieser es kann, zeigt erst der Versuch.
- Ob iOS den Text auch dann schickt, wenn die Vorschau auf dem Sperrbildschirm auf „Wenn entsperrt“ steht, weiß ich
  nicht sicher. Uhren zeigen den Text in der Regel trotzdem; prüfen.

**Grenzen:** nur in Bluetooth-Reichweite (rund 10 m, durch Wände weniger), nur wenn der PC läuft, nur Text (keine
Bilder, Sprachnachrichten, Dokumente), Texte gekürzt (die Länge fordert der PC an), keine Antwort aus der Mitteilung
heraus (ANCS kennt nur die Aktionen „positiv“ und „negativ“, bei WhatsApp also höchstens „Löschen“). Unterwegs gibt es
nichts.

**Risiken:** gering. Kein Verstoß gegen Bedingungen, keine Zugangsdaten. Der PC sieht aber alle Mitteilungen aller
Apps (Banking-Codes, Zwei-Faktor-Codes, private Nachrichten Dritter). Darum: Filter am PC auf eine Liste erlaubter Apps
(zuerst nur WhatsApp), Ablage nur lokal im Inbox-Ordner des Gateways (30 Tage, wie heute), nie ins Vault.

**Aufwand:** ein Nachtbau für den Dienst am PC (systemd-Benutzerdienst, Filter, `inbox_put`), dazu einmal Koppeln am
iPhone durch Martin. Vorher der Versuch, ob Stick und BlueZ mitspielen (siehe unten).

### (b) Anhänge über „Teilen“ an Relay

**Wie es geht:** In WhatsApp ein Bild, eine PDF oder eine Sprachnachricht lange drücken, „Teilen“, Relay wählen. Das
gibt es seit Version 0.3.2 („In Relay öffnen“, Ziel „Ins Vault einsortieren“ oder eine Sitzung).

**Machbarkeit:** vorhanden. Relay erscheint nur bei Dateien (Bilder, Dokumente), nicht bei reinem Text oder Links;
dafür bräuchte es eine Share Extension, die mit der kostenlosen Apple-ID unter SideStore nicht geht.

**Verbesserung:** Ein Kurzbefehl „An Relay“ im Teilen-Menü (Kurzbefehle-App, „Im Share-Sheet anzeigen“) kann auch
Text und Links annehmen und an Relay geben. Dafür braucht Relay eine Kurzbefehl-Aktion „Text an Relay“ (App Intent,
geht ohne Entitlement, Jarvis nutzt das schon). Das passt zu Stufe 2 des Telefonzugriffs (Kurzbefehle).

**Risiken:** keine. Martin entscheidet je Nachricht selbst, was der Agent sieht.

**Aufwand:** keiner für den Stand heute; der Kurzbefehl-Weg etwa ein halber Nachtbau zusammen mit Stufe 2.

### (c) WhatsApp direkt

**(c1) Offizielle WhatsApp Business Cloud API (Meta).** Eine eigene Telefonnummer für die KI (nicht Martins Nummer),
ein Meta-Business-Konto, eine App im Meta-Entwicklerportal. Martin schreibt der KI-Nummer, Meta schickt jede Nachricht
samt Anhängen an eine Webadresse (Webhook), die KI antwortet über die API. Antworten auf Nachrichten, die Martin selbst
geschickt hat, sind innerhalb von 24 Stunden frei formulierbar; danach nur mit vorab genehmigten Vorlagen.
- Machbar und erlaubt. Liest aber **nicht** Martins eigene Chats mit anderen, sondern nur, was an die KI-Nummer geht.
  Für „Nachrichten von Freunden mitlesen“ taugt der Weg nicht.
- Braucht eine aus dem Internet erreichbare HTTPS-Adresse. Relay hat bewusst keinen öffentlichen Server; nötig wäre
  ein Tunnel (zum Beispiel Cloudflare Tunnel) zum PC oder zum Pi. Das ist neue Angriffsfläche.
- Kosten: Gespräche, die Martin beginnt, waren zuletzt kostenlos; Vorlagen kosten je Nachricht. Vor einer
  Entscheidung aktuell nachlesen.
- Aufwand: zwei Nachtbauten (Webhook, Anbindung ans Gateway wie Jarvis, Medien herunterladen) plus Einrichtung durch
  Martin bei Meta (Nummer, Konto, eventuell Unternehmensprüfung).

**(c2) Inoffizielle Bibliotheken als verknüpftes Gerät** (wie WhatsApp Web, zum Beispiel „whatsmeow“ in Go oder
„Baileys“ in JavaScript). Der PC meldet sich per QR-Code als weiteres Gerät an Martins WhatsApp an und sieht alle
Chats, Gruppen und Anhänge, kann auch senden.
- Technisch der vollständigste Weg.
- Verstößt gegen die Nutzungsbedingungen von WhatsApp. Meta sperrt erkannte Konten, auch dauerhaft; dann ist Martins
  WhatsApp weg. Die Bibliotheken brechen bei Änderungen am Protokoll.
- Der PC hält dann die Schlüssel zu Martins gesamtem WhatsApp und die Nachrichten Dritter, die nicht zugestimmt haben
  (Datenschutz der Kontakte).
- Empfehlung: nicht machen.

### (d) Android-Zweitgerät als verknüpftes Gerät

**Wie es geht:** WhatsApp erlaubt offiziell bis zu vier verknüpfte Geräte, darunter ein Android-Tablet oder ein
zweites Android-Telefon („Companion“). Auf so einem Gerät (ein altes Android-Telefon reicht) läuft WhatsApp als
verknüpftes Gerät und daneben die Relay-Android-App mit ihrer Telefon-Bridge. Die liest die WhatsApp-Mitteilungen
über die Android-Schnittstelle und gibt sie per `inbox_put` ans Gateway. Das Gerät liegt zu Hause am Strom im WLAN.
- Erlaubt: offizielles verknüpftes Gerät, offizielle Android-Schnittstelle. Funktioniert unabhängig von Bluetooth und
  davon, wo das iPhone ist.
- Text wie bei (a). Anhänge sind auf dem Zweitgerät vorhanden; ein Agent käme mit einer Erweiterung der Android-App
  heran (nicht gebaut, Aufwand offen).
- Offene Punkte (nicht geprüft): ob WhatsApp auf einem verknüpften Android-Telefon alle Mitteilungen zuverlässig zeigt,
  und ob die Relay-Android-App auf Martins Stand noch zum Gateway passt.
- Risiken: wie (a), das Zweitgerät sieht alle WhatsApp-Chats. Es braucht eine Bildschirmsperre und gehört nicht
  in fremde Hände.
- Aufwand: kaum Code (die Bridge gibt es), Einrichtung durch Martin, ein Gerät.

## Vergleich

| Weg | Liest WhatsApp-Texte | Anhänge | Unterwegs | Erlaubt | Aufwand |
|---|---|---|---|---|---|
| (a) ANCS am PC | ja, gekürzt | nein | nein (nur in Reichweite des PCs) | ja | 1 Nachtbau, Versuch vorher |
| (b) Teilen an Relay | nur was Martin teilt | ja | ja | ja | vorhanden |
| (c1) Business API | nur Nachrichten an die KI-Nummer | ja | ja | ja | 2 Nachtbauten, Meta-Konto, Tunnel |
| (c2) Inoffizielle Bibliothek | ja, alles | ja | ja | **nein**, Sperre möglich | 1 bis 2 Nachtbauten |
| (d) Android-Zweitgerät | ja | später | ja (Gerät zu Hause) | ja | Einrichtung, ein Gerät |

## Empfehlung

1. **Sofort ohne Bau:** (b) nutzen. Anhänge aus WhatsApp per „Teilen“ an Relay, das geht heute.
2. **Zum Mitlesen:** zuerst (a) als Versuch, weil kein Gerät und kein Konto nötig ist. Klappt der Funkstick nicht als
   Peripherie, (d) mit einem alten Android-Telefon, falls eines da ist.
3. **„Mit der KI über WhatsApp schreiben“:** nur über (c1), mit eigener Nummer, wenn Martin das wirklich braucht. Jarvis
   in Relay und der Sprachmodus decken das heute schon ab.
4. **Nicht:** (c2). Das Risiko, das eigene WhatsApp-Konto zu verlieren, steht in keinem Verhältnis.

Für alle Wege gilt: Inhalte aus fremden Nachrichten sind für Agenten nicht vertrauenswürdig (keine Anweisungen daraus
befolgen, wie heute bei `phone_inbox`), nur erlaubte Apps durchlassen, nichts davon ins Vault oder auf GitHub.

## Befund am Rechner (7. November 2026, nur lesend, ohne sudo)

- Bluetooth-Funkstick vorhanden: `hci0`, USB `0a12:0001` (CSR), Treiber `btusb`, nicht blockiert (`rfkill`).
- BlueZ 5.87 ist installiert, `python-dbus` und `python-gobject` auch.
- Der Dienst `bluetooth` ist aus und nicht aktiviert, `bluetoothctl` fehlt (Paket `bluez-utils` nicht installiert).
  Ohne beides lässt sich nichts weiter prüfen; Starten und Installieren braucht sudo.
- Befehle für Martin stehen in „Offene Befehle“ im Vault: `sudo pacman -S --needed bluez-utils` und
  `sudo systemctl enable --now bluetooth`. Danach prüft ein Agent ohne sudo mit `bluetoothctl show`, ob der Stick die
  Rolle „peripheral“ und Low Energy meldet. Erst dann lohnt der Versuch mit dem iPhone (Koppeln braucht Martin).

## Fragen an Martin

1. Soll (a) ANCS am PC ausprobiert werden? Dafür die zwei Befehle aus „Offene Befehle“ ausführen und einmal am iPhone
   koppeln. Empfehlung: ja.
2. Liegt ein altes Android-Telefon herum, das als verknüpftes WhatsApp-Gerät (d) zu Hause bleiben könnte? Empfehlung:
   nur, falls (a) nicht klappt.
3. Willst du wirklich mit der KI über WhatsApp schreiben (eigene Nummer, Meta-Konto, Tunnel nach außen, c1)?
   Empfehlung: nein, vorerst Jarvis und Sprachmodus.
4. Inoffizielle Bibliotheken (c2) ausschließen? Empfehlung: ja, ausschließen.
