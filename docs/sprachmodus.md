# Sprachmodus („Autofahrt“)

Stand: 2026-11-07, Version 0.3.9. Relay ohne Lesen nutzen, etwa beim Autofahren: Die App liest offene Rückfragen der
Agenten vor, Martin antwortet per Sprache, hört die Antwort zur Kontrolle und gibt sie mit „senden“ frei. Danach kann
er per Sprache mit einer laufenden Sitzung sprechen.

## Öffnen

- Menü → „Hinweise“ → ganz oben „Sprachmodus“ (mit Anzahl offener Rückfragen)
- In einer Rückfrage unter „Hinweise“: „Im Sprachmodus beantworten“
- Siri oder Aktionstaste: Kurzbefehl „Sprachmodus in Relay“ (auch „Rückfragen in Relay“). Über CarPlay-Siri startet
  er die App auf dem iPhone; ist das iPhone gesperrt, verlangt iOS zuerst das Entsperren.

Solange der Sprachmodus offen ist, bleibt der Bildschirm an. „Beenden“ oben rechts oder Zurück schließt ihn sofort,
ohne weiter zu sprechen.

## Ablauf Rückfragen

1. Die älteste offene Rückfrage wird vorgelesen: „Rückfrage 1 von 2, von relay-ios. Soll ich …? Empfehlung: …“. Nur
   Frage und Empfehlung, der Kontext nicht (der steht unter „Hinweise“). Beim ersten Mal kommt der Satz „Sag ja, nein
   oder deine Antwort.“ dazu.
2. Die App hört zu. Möglich sind
   - „ja“ (auch „okay“, „einverstanden“, „mach das“): Antwort „ja“, also die Empfehlung
   - „nein“: Antwort „nein“
   - ein eigener Satz: wird die Antwort. Ein ganzer Satz zählt immer als Antwort, auch wenn er mit „nein“ beginnt
   - „wiederholen“, „wie bitte“, „nochmal“: die Frage noch einmal
   - „später“, „überspringen“, „weiter“: diese Rückfrage liegen lassen, sie bleibt unter „Hinweise“ offen
   - „stopp“, „beenden“: Sprachmodus aus
3. Kontrolle: „Ich antworte: erst nach dem Backup. Senden oder nochmal?“ Bei „ja“ mit Empfehlung: „Ich antworte: ja,
   also …“.
   - „senden“, „ja“, „passt“, „richtig“: geht an `rueckfrage` (wie das Antwortfeld unter „Hinweise“)
   - „nochmal“, „nein“, „falsch“: neu sprechen
   - ein anderer Satz: ersetzt die Antwort und wird wieder vorgelesen. So korrigiert man sich in einem Schritt.
4. „Gesendet.“, dann die nächste Rückfrage. Sind alle erledigt: „Ich lese neue vor, sobald sie kommen.“ Kommt eine neue
   Rückfrage, während der Sprachmodus offen ist, liest er sie sofort vor. Wird eine Rückfrage anderswo beantwortet (in
   der Mitteilung, am PC), fällt sie heraus.
5. Klappt das Senden nicht (keine Verbindung), sagt die App den Grund und fragt erneut nach „senden“. Die Antwort geht
   nicht verloren.

Zweimal hintereinander nichts gehört: Die App pausiert, damit das Mikrofon nicht endlos offen bleibt. Der große Knopf
„Sprechen“ macht weiter.

Alles, was man sagen kann, geht auch über große Knöpfe: Ja, Nein, Wiederholen, Später, Senden, Nochmal.

## Gespräch mit einer Sitzung

Wartet der Sprachmodus auf Rückfragen, stehen darunter die vier zuletzt aktiven Sitzungen und „Mit Jarvis sprechen“.

1. Tipp auf eine Sitzung: „Gespräch mit webapp. Was soll ich sagen?“
2. Martin spricht, die App liest vor: „An webapp: … Senden oder nochmal?“ Gleiche Regeln wie oben.
3. Nach „senden“ geht der Text an die Sitzung. Die App wartet, bis die Sitzung gearbeitet hat und fertig ist
   (höchstens 15 Minuten), und liest die Antwort gekürzt vor. Wartet die Sitzung auf eine Auswahl, kommen Frage und
   Optionen dazu.
4. Danach hört die App wieder zu. „stopp“, „danke“ oder zweimal Stille beenden das Gespräch; der Sprachmodus liest
   dann Rückfragen vor, die in der Zwischenzeit gekommen sind.

„Mit Jarvis sprechen“ öffnet Jarvis im Gesprächsmodus (wie bisher).

## Geklärte Fragen aus dem Backlog

**Was geht unter SideStore im Hintergrund?** Hintergrund-Audio ist ein Eintrag in der Info.plist
(`UIBackgroundModes: audio`, in Relay schon vorhanden) und kein Entitlement. Es funktioniert deshalb auch mit
kostenloser Apple-ID über SideStore. Solange die App vorliest oder zuhört, läuft das bei gesperrtem Bildschirm
weiter. Wartet sie auf neue Rückfragen und ist der Bildschirm gesperrt, hält iOS die App nach kurzer Zeit an; neue
Rückfragen kommen dann wie bisher als Mitteilung. Darum hält der Sprachmodus den Bildschirm an (im Auto am Halter
sinnvoll). Ob die Spracherkennung bei gesperrtem Bildschirm zuverlässig weiterläuft, ist auf dem Gerät noch nicht
geprüft. Eine eigene CarPlay-Oberfläche geht nicht: dafür vergibt Apple ein besonderes Entitlement, das es für
SideStore-Apps nicht gibt. Der Ton läuft trotzdem über CarPlay oder Bluetooth, das Mikrofon des Autos wird genutzt.

**Wer erzeugt die Kurzfassung für die Sprache?** Bei Rückfragen niemand: Der Agent schreibt Frage und Empfehlung ohnehin
knapp, die App liest nur diese beiden Teile. Bei Antworten einer Sitzung das Gateway (`speak_summary`, ein bis drei
Sätze, kostet wenige Haiku-Token wie das Vorlesen fertiger Sitzungen). Scheitert das, kürzt die App selbst: die ersten
Sätze der letzten Nachricht, ohne Code, Links nur als „Link“, Pfade nur mit Dateinamen.

**Wie korrigiert Martin eine falsch verstandene Antwort?** Jede Antwort wird vor dem Senden vorgelesen. „nochmal“
verwirft sie, ein neuer Satz ersetzt sie, erst „senden“ schickt. Erkennt die App ein Wort immer wieder falsch, hilft
„Erkennung korrigieren“ in Jarvis (gleiche Erkennung, gleiches Vokabular).

## Technik

- RelayCore `Drive.swift`: `DriveText` (Wörter, Ansagen), `DriveSession` (Ablauf Rückfragen), `DriveTalk` (Gespräch
  mit einer Sitzung), `DriveQueue` (offene Rückfragen aus den Hinweisen). Tests: `DriveTests`.
- App `DriveView.swift`: `DriveController` führt die Schritte aus (Vorlesen und Zuhören über `VoiceIO`, Antwort über
  `answerQuestion` wie unter „Hinweise“, Nachricht an die Sitzung über `send`, Warten über den Sitzungszustand).
  Während der Sprachmodus offen ist, liest „Fertige Sitzungen vorlesen“ nichts zusätzlich vor.
- UI-Test `test24_DriveMode` (ohne Mikrofon und Stimme, über die Knöpfe): Rückfrage öffnen, „Ja“, „Senden“, prüft
  `inbox_put` mit Antwort „ja“.
- Am Gateway ist nichts zu ändern.
