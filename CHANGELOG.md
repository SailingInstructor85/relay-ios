# Changelog

Versionen der iPhone-App Relay, neueste oben. Aus dem Abschnitt der getaggten Version entstehen der Release-Text auf GitHub und die Versionsbeschreibung in SideStore („Neu in dieser Version“). Je Version: **Neu**, **Geändert**, **Behoben**.

## 0.3.15 (2026-11-10)

**Neu**
- Klappt die Verbindung zum PC nicht, sagt Relay jetzt, woran es liegt, statt nur eine rohe Fehlermeldung zu zeigen: kein Netz, Tailscale aus, kein Weg zum PC (nur die Heimnetz-Adresse eingetragen und unterwegs), PC schläft, PC nicht erreichbar, SSH-Dienst läuft nicht, PC lehnt dieses iPhone ab, Host-Schlüssel passt nicht, Gateway läuft nicht.
- Zu jedem Grund steht über der Sitzungsliste, was zu tun ist, mit den passenden Knöpfen: „Tailscale verbinden“ und „Tailscale öffnen“, „iOS-Einstellungen“, „Adresse prüfen“, „Befehl kopieren“ (Startbefehl für das Gateway oder der Befehl, der den Schlüssel dieses iPhones am PC einträgt) und „Neuen Schlüssel übernehmen“ (mit Rückfrage).

**Geändert**
- Diktat im Chat und im Vault-Chat: Die Musik anderer Apps läuft weiter, sobald die Aufnahme endet, auch wenn der diktierte Text noch im Feld steht. Bisher blieb sie aus, bis die Nachricht gesendet oder das Feld geleert war.
- Jarvis ohne „Antworten vorlesen“ gibt die Musik gleich nach der Aufnahme wieder frei.
- Trennt Relay die Verbindung selbst (zurück aus dem Hintergrund, „Erneut“), blitzt kein Fehler mehr auf.
- „Kein Weg zum PC“ erscheint nur noch, wenn das iPhone nicht im WLAN ist. Zuhause bei ausgeschaltetem PC steht jetzt „PC nicht erreichbar“.

**Behoben**
- Spotify lief während der Aufnahme leise und blechern weiter und kam danach nicht normal zurück. Das war das Verhalten bis Version 0.3.11; die Korrektur steckt seit 0.3.12 in der App. Bitte in SideStore auf die aktuelle Version aktualisieren.
- Gab iOS das Audio nach Aufnahme oder Vorlesen nicht sofort zurück, blieb die Musik anderer Apps aus. Relay versucht die Freigabe jetzt noch dreimal und schreibt Übernahme, Freigabe und Unterbrechungen ins Nutzungsprotokoll.

## 0.3.14 (2026-11-10)

**Behoben**
- Das iPhone sperrte sich mitten im Diktat. Solange eine Mikrofon-Aufnahme läuft (Diktat im Chat oder im Vault-Chat, Jarvis), bleibt der Bildschirm jetzt an, höchstens 10 Minuten am Stück. Endet die Aufnahme früher, gilt sofort wieder die normale automatische Sperre.

**Geändert**
- „Bildschirm bleibt an“ beim Zuschauen (60 s nach der letzten Berührung im Chat) und die Aufnahme gelten nebeneinander: Der Bildschirm geht erst aus, wenn keins von beiden mehr greift. Im Sprachmodus bleibt er wie bisher durchgehend an, auch wenn dort eine Aufnahme endet.

## 0.3.13 (2026-11-09)

**Neu**
- Mehrere Fotos auf einmal: In der Büroklammer heißt der Punkt jetzt „Fotos oder Videos“. In der Mediathek wählst du beliebig viele Fotos und Videos aus, die Reihenfolge deiner Auswahl bleibt erhalten.
- Die gewählten Fotos erscheinen zuerst als Vorschau über dem Eingabefeld. Mit dem kleinen Kreuz nimmst du einzelne wieder heraus, „Verwerfen“ leert die Auswahl. Erst „3 Fotos hochladen“ (oder Senden) lädt alle nacheinander hoch, der Fortschritt steht darüber („Lade 2 von 3 hoch…“). Danach stehen die Pfade wie bisher je in einer Zeile in der Nachricht.

**Geändert**
- Relay lädt ein gewähltes Foto nicht mehr sofort hoch, sondern wartet auf deinen Tipp. Eine zweite Auswahl kommt hinten zur Vorschau dazu.
- Klappt ein Upload nicht, bleiben dieses und die folgenden Fotos in der Vorschau, die schon hochgeladenen stehen im Feld. Ein zweiter Tipp versucht den Rest erneut.
- Im Chat mit dem Vault-Agenten wird jedes gewählte Foto ein eigener Anhang.

## 0.3.12 (2026-11-09)

**Neu**
- Hilfe, wenn Tailscale aus ist: Erreicht Relay den PC nicht, weil iOS Tailscale im Hintergrund beendet hat, steht über der Sitzungsliste „Keine Verbindung. Tailscale ist vermutlich aus.“ mit dem Knopf „Tailscale verbinden“. Er startet deinen Kurzbefehl mit der Tailscale-Aktion „Connect“, springt zurück zu Relay und verbindet sofort neu. Der Hinweis kommt nur, wenn dein PC über Tailscale erreicht wird und das iPhone gerade keine Tailscale-Verbindung hat. Ist Tailscale an und nur der PC still, bleibt er weg.
- Einstellungen → Status → „Tailscale verbinden“: Name des Kurzbefehls und eine kurze Anleitung zum Anlegen in der Kurzbefehle-App. Ohne Namen öffnet der Knopf die Tailscale-App.
- Nachricht an den Vault-Agenten auch ohne Verbindung: Oben in der Sitzungsliste steht dann „Nachricht an Vault-Agent“. Du kannst schreiben, diktieren und Fotos oder Dateien anhängen. Alles wartet auf dem iPhone, an jeder Nachricht steht „wartet auf Verbindung“, Bearbeiten und Verwerfen gehen auch. Sobald der PC erreichbar ist, startet Relay einen Agenten im Vault mit allen wartenden Nachrichten in der richtigen Reihenfolge. Spätere Nachrichten gehen in dieselbe Sitzung, solange sie läuft. Nichts wird doppelt gesendet.

**Geändert**
- Kommt Tailscale wieder hoch, versucht Relay die Verbindung sofort statt erst beim nächsten Intervall.

**Behoben**
- Musik spielte während einer Aufnahme mit seltsamem Klang weiter (etwa Spotify im Auto über Bluetooth). Diktat, Jarvis, Sprachmodus und Vorlesen pausieren andere Apps jetzt, statt sie nur leiser zu stellen. Ist die Nachricht fertig (gesendet, Feld geleert, Vorlesen zu Ende oder Ansicht verlassen), spielt die Musik von selbst weiter. Zwischen Aufnahme und Kontrollvorlesen bleibt sie aus.

## 0.3.11 (2026-11-07)

Braucht für den Telefonzugriff das aktuelle Gateway (auf dem PC schon eingespielt).

**Neu**
- Telefonzugriff für Agenten (Stufe 1, nur Lesen): Agenten am PC können über Relay Geräteinfos (Akku, freier Speicher, iOS-Version, Netz), Dateien aus Ordnern, die du freigibst, die neuesten Fotos und die Zwischenablage abfragen. Einstellungen → „Telefonzugriff für Agenten“.
- Jeder Bereich hat einen eigenen Schalter, anfangs sind alle aus. Ist ein Bereich an, liest der Agent ohne Rückfrage, und jede Anfrage steht im Verlauf (wer, was, warum, Ergebnis, 30 Tage, ohne Inhalte).
- Not-Aus ganz oben: An lehnt Relay jede Anfrage ab, auch die schon wartenden.
- Ordner freigeben über die Dateien-App, auch aus Google Drive, wenn die Google-Drive-App dort als Speicherort aktiv ist. Relay speichert keine Zugangsdaten. Jeder Ordner bekommt einen kurzen Namen, den du per langem Drücken änderst.
- Ist Relay zu, wartet die Anfrage. Wartet sie länger als 5 Minuten, kommt einmal ein Hinweis, Relay zu öffnen, nicht in den Ruhezeiten. Die Zwischenablage liest Relay nur, solange die App offen ist.

**Geändert**
- Der Text zur Fotofreigabe nennt jetzt auch den Telefonzugriff.

## 0.3.10 (2026-11-07)

Braucht für die Behebungen beim Senden und bei „Alle Sitzungen beenden“ das aktuelle Gateway (auf dem PC schon eingespielt).

**Neu**
- Jarvis erklärt sich: Solange der Verlauf leer ist, steht oben, was Jarvis ist (der eingebaute Sprachassistent von Relay für Fragen an deinen PC und deine Sitzungen, kein Agent von Christopher) und wie das Mikrofon funktioniert.
- „Alle Sitzungen beenden“: Jede Sitzung schreibt vor dem Ende zusätzlich ihren Eintrag ins Agenten-Log der Daily Note, damit der Tag nachvollziehbar bleibt.

**Geändert**
- Nachrichten vom Handy gehen am PC jetzt in zwei Schritten ein: erst der Text, nach einer kurzen Pause das Enter. Danach prüft der PC, ob das Eingabefeld leer ist, und drückt notfalls noch einmal Enter. Bleibt der Text trotzdem stehen, sagt die App das deutlich, statt „gesendet“ zu melden. Erneut senden bietet sie dann nicht an, damit der Text nicht doppelt dasteht.
- „Alle Sitzungen beenden“: Über dem Knopf steht, warum er gesperrt ist (keine Verbindung, nichts gewählt). Sitzungen, die am PC gerade eine Auswahl oder Freigabe zeigen, bleiben mit diesem Grund offen.

**Behoben**
- Jarvis per Sprache: Der rote Knopf während der Aufnahme warf das Gehörte weg. Jetzt kommt der Text ins Schreibfeld und lässt sich ändern und senden. Senden während der Aufnahme schickt Getipptes und Gesprochenes zusammen ab.
- „Alle Sitzungen beenden“ tat nichts, wenn das Blatt geöffnet wurde, bevor die Sitzungsliste geladen war: Es war nichts ausgewählt und der Knopf blieb bei „0 Sitzungen“. Die Auswahl folgt jetzt der Liste, bis du selbst etwas antippst.

## 0.3.9 (2026-11-07)

**Neu**
- Sprachmodus für die Autofahrt: Unter „Hinweise“ ganz oben „Sprachmodus“, in jeder Rückfrage „Im Sprachmodus beantworten“ oder per Siri und Aktionstaste mit „Sprachmodus in Relay“. Relay liest offene Rückfragen der Agenten vor, nur Frage und Empfehlung. Du antwortest mit „ja“, „nein“ oder in eigenen Worten. Die Antwort wird zur Kontrolle vorgelesen und geht erst nach „senden“ an den Agenten. „nochmal“ verwirft sie, ein neuer Satz ersetzt sie. „wiederholen“, „später“ und „stopp“ gehen auch. Neue Rückfragen liest der Sprachmodus sofort vor, solange er offen ist.
- Gespräch mit einer Sitzung per Sprache: Wartet der Sprachmodus, stehen darunter die zuletzt aktiven Sitzungen. Du sprichst, hörst deine Nachricht zur Kontrolle, sagst „senden“, und Relay liest die Antwort der Sitzung gekürzt vor (ohne Code und Pfade). Danach hört die App wieder zu, bis du „stopp“ oder „danke“ sagst.
- Große Knöpfe für alles, was man auch sagen kann (Ja, Nein, Senden, Nochmal, Später). Der Bildschirm bleibt an, der Ton läuft über Bluetooth oder CarPlay.

**Geändert**
- Solange der Sprachmodus offen ist, liest „Fertige Sitzungen vorlesen“ nichts zusätzlich vor, damit nicht zwei Stimmen gleichzeitig sprechen.
- Der Hinweis zur Mikrofonfreigabe nennt jetzt auch den Sprachmodus.

## 0.3.8 (2026-11-07)

Braucht für Nutzungsprotokoll und „Fehler melden“ ein aktuelles Gateway (notifyd nach dem Update neu starten). Mit dem älteren Gateway bleibt das Protokoll auf dem iPhone und geht später mit.

**Neu**
- Nutzungsprotokoll (Einstellungen → Nutzungsprotokoll, standardmäßig an): Die App zeichnet auf, was du tust (Ansicht geöffnet, Sitzung, Tastatur, gesendet, Postausgang, Diktat, Anhang, Stopp), dazu Verbindung, Start nach einem Absturz und Fehler. Ohne Inhalte: von Text, Diktat und Fotos nur Art und Länge. Das Protokoll geht nur an dein eigenes Gateway und bleibt 30 Tage. Bricht die Verbindung beim Senden ab, geht es beim nächsten Mal mit. Schalter zum Abstellen, „Protokoll jetzt senden“ und „Protokoll löschen“.
- „Fehler melden“: kurze Beschreibung, dazu gehen die letzten 10 Minuten des Protokolls an den PC, wo ein Agent sie lesen und den Fehler nachstellen kann. Mit dem Haken „Inhalte mitsenden“ auch der Text, den du in diesen Minuten gesendet oder diktiert hast. Fotos nie, nur ihr Pfad.
- Konzept „Telefonzugriff für Agenten“ für Version 0.4.0 (nur Dokumentation, noch keine Funktion): was Agenten über Relay am iPhone lesen und tun dürfen, mit welchen Freigaben und Bestätigungen.

**Geändert**
- Der Knopf „Tastatur ausblenden“ sitzt jetzt rechts in der Zeile mit den Schnellantworten über dem Eingabefeld und nicht mehr in der Leiste über der Tastatur. Er erscheint nur bei offener Tastatur; ohne Schnellantworten bekommt er eine eigene schmale Zeile.

**Behoben**
- Der Knopf „Tastatur ausblenden“ verdeckte Senden und Mikrofon teilweise. Beide sind bei offener Tastatur wieder frei antippbar.

## 0.3.7 (2026-11-07)

Braucht für das Symbol „Am PC offen“ ein aktuelles Gateway (notifyd nach dem Update neu starten). Die App läuft auch mit dem älteren Gateway, zeigt das Symbol dann nur bei Sitzungen ohne tmux.

**Neu**
- „Am PC offen“: Ein kleines Monitor-Symbol im Chat-Kopf und in der Sitzungsliste zeigt, dass gerade ein Terminal am PC die Sitzung zeigt. Geht am PC ein Terminal auf oder zu, folgt das Symbol innerhalb weniger Sekunden. Nur Anzeige, nichts wird gesperrt und nichts vor dem Senden gefragt.
- Anleitung „Handy und PC in derselben Sitzung“: Wie `claude` am PC automatisch in einer Sitzung startet, in die auch das Handy tippen kann (Wrapper für die Shell), dazu eine tmux-Einstellung, damit Mausrad, Markieren, Kopieren und Farben wie bisher funktionieren, und was mit Sitzungen passiert, deren Fenster nur geschlossen wurde.

**Geändert**
- Sitzung am PC in einem Terminal ohne tmux: Die App fragt nicht mehr von selbst „Am PC beenden und hier fortsetzen?“. Die Nachricht bleibt im Postausgang, über der Eingabe steht „Am PC in einem Terminal ohne tmux offen: vom Handy nur mitlesen. Nachrichten warten im Postausgang.“ Wer die Sitzung trotzdem auf tmux umziehen will, tippt in der Postausgangszeile „Am PC beenden und hier fortsetzen…“ und bestätigt. Ohne das passiert am PC nichts.

**Behoben**
- „Eingaben erscheinen nicht mehr auf beiden Geräten“: nachgestellt, kein Fehler im Code. In Sitzungen, die die App gestartet hat (tmux), kommen Nachrichten in beiden Richtungen an. Betroffen sind nur Sitzungen, die am PC als nacktes `claude` ohne tmux laufen: dort liest das Handy mit, kann aber nichts eintippen. Abhilfe ist der Wrapper aus der neuen Anleitung.

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
