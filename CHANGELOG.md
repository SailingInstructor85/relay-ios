# Changelog

Versionen der iPhone-App Relay, neueste oben. Aus dem Abschnitt der getaggten Version entstehen der Release-Text auf GitHub und die Versionsbeschreibung in SideStore („Neu in dieser Version“). Je Version: **Neu**, **Geändert**, **Behoben**.

## 0.4.11 (2026-11-26)

**Behoben**
- Jarvis blieb stumm, wenn sich das iPhone sperrte, während du auf eine Antwort gewartet hast. Die Ursache steht jetzt fest: Im Hintergrund lässt iOS die Stimme Supertonic nicht auf den Grafikchip, und die App bekommt die Tonausgabe nicht mehr. Dagegen hilft jetzt dreierlei. Erstens bleibt der Bildschirm an, solange eine gesprochene Frage auf ihre Antwort wartet, die vorgelesen werden soll (höchstens zehn Minuten). Zweitens rechnet Supertonic im Hintergrund auf dem Prozessor, das erlaubt iOS. Drittens holt Jarvis eine Antwort nach, die im Hintergrund nicht zu hören gewesen wäre: Er liest sie vor, sobald du Relay wieder öffnest, sofern das innerhalb von zwei Minuten geschieht. Später steht sie nur im Chat.
- Supertonic: Scheitert ein Satz, versucht die App ihn ein zweites Mal auf dem Prozessor. Erst wenn auch das scheitert, spricht die Apple-Stimme diesen Satz. Bisher schaltete ein einzelner Vorfall im Hintergrund Supertonic bis zum nächsten Start der App ab, das passiert nicht mehr.

**Geändert**
- Supertonic: Nach dem Laden rechnet die Stimme einmal einen kurzen Satz, ohne ihn abzuspielen. Der erste Satz nach dem Laden brauchte bisher über sieben Sekunden, die folgenden eine halbe. Diese Wartezeit soll damit vor der ersten Antwort liegen statt mittendrin.

Hinweis: Auf einem iPhone ist diese Version noch nicht ausprobiert. Wie schnell Supertonic auf dem Prozessor rechnet, ist nicht gemessen. Die Ablösung des Chiefs auf Zuruf, „Chief hat es“ und Ergebnisse mit Thema im Jarvis-Chat warten weiter auf die Ergänzung am PC (siehe 0.4.10).

## 0.4.10 (2026-11-26)

**Neu**
- Jarvis: Das Eingabefeld bleibt frei, während eine Antwort aussteht. Du kannst sofort die nächste Nachricht schreiben oder sprechen, ohne auf die erste Antwort zu warten. Jede Antwort landet bei ihrer Frage. Stehen mehrere aus, steht das über dem Feld. Gesperrt ist das Senden nur noch, solange angehängte Fotos oder Dokumente hochladen.
- Jarvis: Unter einer Frage steht „Chief hat es“, sobald deine Nachricht am PC angekommen ist. So siehst du gleich, dass sie da ist, auch wenn die Antwort noch dauert.
- Jarvis: Ergebnisse, die erst später fertig werden, stehen mit ihrem Thema als Überschrift im Jarvis-Chat und werden vorgelesen, das Thema zuerst. Ist der Chat gerade zu, kommt eine Mitteilung, ein Tipp darauf öffnet Jarvis. Das Vorlesen folgt dem Schalter „Antworten vorlesen“ im Jarvis-Menü und wartet, bis eine laufende Antwort oder Aufnahme zu Ende ist.
- Jarvis: Im Menü oben rechts steht „Chief ablösen“. Nach einer kurzen Nachfrage schreibt der Chief seine Notizen, danach beginnt am PC eine frische Sitzung, die mit den Notizen weitermacht. Läuft bei ihm noch Hintergrundarbeit, wartet die Ablösung, bis sie fertig ist. Der Verlauf auf dem iPhone bleibt.

**Behoben**
- Jarvis: „Chat löschen“, während eine Antwort noch aussteht, bringt den Verlauf nicht mehr durcheinander.

Hinweis: Sofort wirkt das freie Eingabefeld. „Chief hat es“, die Ergebnisse mit Thema und „Chief ablösen“ brauchen eine Ergänzung am PC. Sie ist vorbereitet und geprüft, aber noch nicht eingespielt. Bis dahin fehlen der Menüpunkt und die Anzeige, sonst ändert sich nichts. Auf einem iPhone ist diese Version noch nicht ausprobiert.

## 0.4.9 (2026-11-26)

**Neu**
- Sitzung über das Befehlsmenü ganz schließen: Im Menü „/“ links neben dem Eingabefeld steht jetzt „/exit · Sitzung schließen“ (bei Codex „/quit · Sitzung schließen“), direkt über „Esc senden“. Nach einer kurzen Nachfrage („Sitzung ganz schließen?“ → „Ganz schließen“) wird der Agent beendet und die Sitzung am PC geschlossen. Das Gespräch bleibt erhalten, die Sitzung steht in der Liste als geschlossen und lässt sich wieder öffnen. Das ist derselbe Weg wie „Sitzung schließen“ im Sitzungsmenü oben rechts. Den Eintrag gibt es nur bei laufenden Sitzungen.

**Geändert**
- Wer „/exit“ oder „/quit“ von Hand ins Feld schreibt und sendet, bekommt dieselbe Nachfrage. Bisher wurde der Befehl nur ins Terminal getippt: Der Agent war dann beendet, die Sitzung am PC stand aber noch. In den Listen des Befehlsmenüs steht „/quit“ deshalb nicht mehr als Befehl zum Einfügen.
- Jarvis-Chat: Fotos und Dokumente, die du über die Büroklammer oder über „Teilen“ an Jarvis gibst, schickt die App jetzt als Upload gekennzeichnet an den PC. So kann der PC ein neues Dokument immer als eigenen Vorgang führen, auch wenn Jarvis gerade eine Rückfrage an dich offen hat. Die Rückfrage beantwortet nur, was du ohne Anhang tippst oder sprichst.

Hinweis: Der Punkt zum Jarvis-Chat wirkt erst, wenn auch der PC das Kennzeichen auswertet. Diese Ergänzung ist vorbereitet und geprüft, aber noch nicht eingespielt. Bis dahin kann ein Dokument, das du während einer offenen Rückfrage schickst, weiter als Antwort auf diese Rückfrage gezählt werden.

## 0.4.8 (2026-11-25)

**Neu**
- Jarvis' Stimme Supertonic hat eine Ausspracheliste. Wörter, die die Stimme falsch liest, bekommt sie vor dem Sprechen in einer Schreibweise, die sie richtig ausspricht. Am Text auf dem Bildschirm ändert sich nichts. Der erste Eintrag ist „Chief“: Bisher las die Stimme den Anfang deutsch, sodass es wie „Schief“ oder „Tief“ klang, jetzt spricht sie „Tschief“. Die Liste wächst, wenn du weitere Wörter meldest. Für die Apple-Stimme gilt sie nicht, die spricht wie bisher.

Hinweis: „Zion“ ist noch nicht dabei. Welche Schreibweise natürlich klingt, lässt sich nur mit den Ohren entscheiden, dafür liegen Hörproben am PC bereit. Am PC („Hey Jarvis“) gilt die Liste erst, wenn sie auch dort eingebaut ist. Geprüft ist „Chief“ am PC mit derselben Stimme, auf dem iPhone ist es noch nicht gehört.

## 0.4.7 (2026-11-24)

**Neu**
- Jarvis: Fotos und Screenshots anhängen ist jetzt deutlicher und vollständiger. In der Büroklammer links am Eingabefeld steht „Fotos, Screenshots oder Videos“ oben. Dort wählst du aus der Mediathek beliebig viele Bilder aus, auch Screenshots. Neu ist „Bild aus Zwischenablage“ für einen eben kopierten Screenshot (der Punkt erscheint nur, wenn ein Bild in der Zwischenablage liegt). „Kamera“ und „Datei“ (Dateien-App) bleiben.
- Jarvis: Angehängte Bilder stehen mit Vorschaubild über der Eingabe, du siehst also vor dem Senden, was mitgeht. Dokumente zeigen wie bisher ein Symbol und den Namen.

**Geändert**
- Jarvis erfährt jetzt, ob er ein Bild oder ein Dokument bekommt. Bei Bildern gibt er den Auftrag so weiter, dass die Sitzung am PC das Bild ansieht, es beim passenden Vorgang ablegt und in die Notiz einbindet, zum Beispiel den Screenshot einer SMS in eine Bewerbungsnotiz. Schreib dazu, wohin es soll. Ohne Text schlägt Jarvis ein Ziel vor und fragt vorher.
- Fotos von der Kamera und Bilder aus der Zwischenablage werden im Jarvis-Chat wie Fotos aus der Mediathek vor dem Hochladen verkleinert (lange Kante 2048 Punkte).

Hinweis: Die Büroklammer im Jarvis-Chat gibt es seit 0.4.4. Fehlt sie bei dir, läuft auf dem iPhone noch eine ältere Version (die Version steht im Tab „Mehr“ ganz unten), dann in SideStore aktualisieren.

## 0.4.6 (2026-11-24)

**Neu**
- Jarvis kann Deutsch mit einer neuen Stimme sprechen: Supertonic 3, Stimme M2. Sie läuft auf dem iPhone, ohne Netz und ohne Cloud. Einschalten: Einstellungen → „Sprache und Stimme“ → „Stimme Deutsch“ → „Supertonic 3 (M2) · auf dem Gerät“, dann in der Zeile darunter einmalig „Modell laden“ (rund 400 MB, am besten im WLAN). „Testen“ spricht einen Probesatz. Beim ersten Mal dauert der Start länger. Zahlen, Daten und Uhrzeiten spricht die Stimme als Wörter. Die Apple-Stimme bleibt voreingestellt, spricht weiter Englisch und springt ein, wenn das Modell fehlt, noch lädt oder scheitert. „Modell löschen“ gibt den Platz wieder frei. Gebaut und automatisch geprüft, auf einem iPhone aber noch nicht gehört.
- Posteingang: Links in einer geöffneten Mail sind jetzt farbig, unterstrichen und antippbar. Webadressen öffnen sich in Safari, Mailadressen im Mailprogramm, immer erst auf dein Tippen. Langes Drücken auf einen Link zeigt die Zieladresse mit „In Safari öffnen“ und „Adresse kopieren“. Kann der Text über das Ziel täuschen (zum Beispiel steht ein anderer Name direkt davor, oder die Adresse beginnt mit einem fremden Namen vor dem @), fragt Relay schon beim Tippen und zeigt, wohin der Link wirklich führt.
- Posteingang: Im Text einer Mail lassen sich per langem Drücken einzelne Wörter und Stellen markieren und kopieren, auch über mehrere Absätze. Bisher ging nur der ganze Absatz.
- Tab „Mehr“: neuer Punkt „Smart Home“ mit der Seite „Fernseher“ (Fernseher einschalten, HDMI 2 aktivieren, Fernsehen, Fernseher ausschalten). Vorbereitet: Geschaltet wird über den PC, und dem PC fehlt dafür noch eine Ergänzung. Bis dahin meldet die Seite „Das Gateway auf dem PC kann den Fernseher noch nicht schalten.“

**Geändert**
- Die Zahlen-Wandlung aus 0.4.5 ist jetzt angeschlossen: Sie gilt für die Stimme Supertonic. Die Apple-Stimme liest Zahlen wie bisher selbst.

## 0.4.5 (2026-11-24)

**Geändert**
- Vorarbeit für Jarvis' neue Stimme (Supertonic 3, Stimme M2): Zahlen, Daten und Uhrzeiten werden für diese Stimme in Wörter gewandelt, zum Beispiel „1081“ in „eintausendeinundachtzig“ und „14:30 Uhr“ in „vierzehn Uhr dreißig“. Zu hören ist das noch nicht. Jarvis spricht weiter mit der Apple-Stimme, bis die neue Stimme eingebaut ist. Dafür müsste die App iOS 18 verlangen, das ist noch nicht entschieden.

**Behoben**
- Keine sichtbare Änderung. Die automatischen Tests halten jetzt fest, was die App tut, falls sie beim Senden ohne Verbindung noch einmal hängen bleibt. Die eigentliche Behebung dieses Hängers kam mit 0.4.4.

## 0.4.4 (2026-11-24)

**Neu**
- Sprachmodus: großer Mikrofon-Knopf für Sprachantworten. „Jetzt sprechen“ bricht das Vorlesen ab und nimmt sofort auf, du musst die Ansage nicht zu Ende hören. Während der Aufnahme heißt der Knopf „Fertig“ und beendet sie sofort, ohne die Sprechpause abzuwarten. Er steht über den übrigen Knöpfen, solange eine Antwort möglich ist, auch im Gespräch mit einer Sitzung.
- Jarvis: Büroklammer links am Eingabefeld, um Dokumente in den Chat zu geben (Datei, Fotos oder Videos, Kamera). Die Dokumente stehen als Marken über der Eingabe und gehen mit der nächsten Nachricht mit, getippt oder gesprochen. Jarvis gibt sie an die passende Sitzung weiter oder startet eine neue dafür. Schreibst du nichts dazu, schlägt er vor, wohin es gehört, und fragt vorher.
- Jarvis: Eine Trennlinie im Verlauf zeigt, wo am PC ein neues Gespräch begonnen hat (jeden Tag um 4 Uhr). Was davor steht, weiß Jarvis nicht mehr.

**Geändert**
- Teilen an Relay landet jetzt bei Jarvis: Im Blatt ist „An Jarvis geben“ vorausgewählt. Die Datei geht an den PC, Jarvis öffnet sich mit deiner Nachricht und verteilt sie. „Neue Sitzung“, „Ins Vault einsortieren“, „In Dokumente ablegen“ und eine bestehende Sitzung gibt es weiter, sie gelten nach Antippen.
- Vorbereitet: Knopf „Neues Gespräch beginnen“ im Jarvis-Menü mit Anzeige, wie voll das Gespräch am PC ist. Beides erscheint erst, wenn der PC die Auskunft liefert. Dafür fehlt am PC noch eine kleine Ergänzung. Bis dahin beginnt Jarvis wie bisher täglich um 4 Uhr und bei sehr langem Verlauf von selbst neu.

## 0.4.3 (2026-11-24)

**Neu**
- Jarvis: In den Antworten lässt sich jetzt per langem Drücken Text markieren. Mit den Griffen wählst du genau den Teil, den du kopieren willst, auch über mehrere Absätze. Bisher gab es nur „Kopieren“ für den ganzen Absatz.

**Geändert**
- Chat: Der Knopf „Tastatur ausblenden“ ist wieder direkt sichtbar. Sobald die Tastatur offen ist, steht er als runder Knopf rechts über dem Eingabefeld, ein Tipp genügt. Der Eintrag im Befehlsmenü („/“) ist dafür entfallen.
- Chat: Lesemodus und Live-Bildschirm stehen jetzt oben im Sitzungsmenü (die drei Punkte oben rechts). Die beiden eigenen Knöpfe im Kopf sind weg, damit der Titel Platz hat.

**Behoben**
- Chat: Der Name der Sitzung und die Angabe „Claude“ oder „Codex“ rutschten im Kopf unter den Zurück-Knopf.

## 0.4.2 (2026-11-24)

**Neu**
- Rückfrage jetzt: Sind Rückfragen offen, zeigt Relay beim Öffnen ein Blatt mit der ältesten, mit vollem Wortlaut, Kontext und Empfehlung. Darunter „Ja (Empfehlung)“, „Antworten“ und „Später“. Nach einer Antwort kommt die nächste offene. „Später“ lässt das Blatt zu, bis eine neue Rückfrage eintrifft.
- Rückfragen: kleiner Knopf „Erledigt“ auf der Karte in Dein Zug und im Hinweis. Er schließt eine Rückfrage ohne Antwort, nach einer kurzen Nachfrage. Der Agent bekommt „(verworfen)“ als Antwort.

**Geändert**
- Rückfragen, die du woanders beantwortet hast (am PC, im Terminal, über den Assistenten, auf einem anderen Gerät), verschwinden jetzt auch in Relay: sofort, oder beim nächsten Verbinden. Der Stand am PC gilt.
- Antwortest du auf eine Rückfrage, die schon beantwortet ist, steht dort „Schon beantwortet: …“ statt einer Fehlermeldung.
- Vorbereitet: Ein leeres Terminal nach `/clear` am PC zählt in Relay nicht mehr als wartend und steht nur noch unter „Zuletzt“, sobald der PC es als solches meldet. Dafür fehlt am PC noch eine kleine Ergänzung.

**Behoben**
- Alte, längst beantwortete Rückfragen blieben in Dein Zug und im Sprachmodus bis zu 14 Tage als offen stehen.

## 0.4.1 (2026-11-24)

**Neu**
- Jarvis: deutlicher Knopf „Vorlesen stoppen“, solange Jarvis vorliest. Nach dem Stopp kommt keine Restsprache mehr.

**Geändert**
- Updates kommen nur noch über die normale App Relay. Die Testapp „Relay Beta“ bekommt keine neuen Fassungen mehr und kann gelöscht werden.

## 0.4.0 (2026-11-23)

**Neu**
- Neues Design mit fünf Tabs unten: Heute, Dein Zug, Posteingang, Sitzungen und Mehr. Das bisherige Hauptmenü steckt jetzt im Tab Mehr.
- Tab Heute: Kopfzeile mit Kennzahlen, „Braucht dich“, Karte für den Assistenten, deine Sitzungen als Karten und eine Kalenderkarte mit den Terminen des Tages und einer Wochenliste.
- Tab Dein Zug: Rückfragen, Freigaben, Bestätigungen, wartende Sitzungen und Cloud-Sitzungen gesammelt als Karten.
- Tab Posteingang: Mails nach Tag sortiert, mit Suche, Mailansicht und Vorschlägen zum Aufräumen (nur zur Ansicht).

**Geändert**
- Warmer Hintergrund, Karten und Serifenschrift für Titel und Antworten, in hell und dunkel. Das gilt auch für Sitzungsliste, Chat und Jarvis.
- Chat-Eingabe: Die festen Reihen mit Schnellantworten und Slash-Befehlen sind weg. Befehle gibt es über ein Menü an der Eingabeleiste.
- Enthält alles aus 0.3.20 („Ins Vault einsortieren“ fragt nach dem Zielordner).

## 0.3.20 (2026-11-23)

**Geändert**
- Teilen an Relay, Ziel „Ins Vault einsortieren“: Der Agent legt die Datei nicht mehr pauschal im Anhänge-Ordner ab. Er legt sie zuerst in die Inbox, liest sie und sucht den Ordner, in dem die übrigen Unterlagen des Vorgangs liegen, im Vault und in deinem Dokumenten-Ordner. Dann schlägt er dir im Chat ein bis drei Zielordner mit Dateinamen und eine passende Notiz vor und fragt, wohin es gehört. Verschoben wird erst nach deiner Antwort.
- Dabei gilt: keine neuen Ordner ohne dein Ja, nichts wird überschrieben, und das Datum im Dateinamen stammt nur aus dem Dokument selbst.
- Die Beschreibungen im Teilen-Blatt und in Einstellungen → Ablage nennen das neue Vorgehen.

**Behoben**
- Ein Schreiben zu einem laufenden Vorgang (zum Beispiel eine Ladung in einem Gerichtsverfahren) landete im Sammelordner für Anhänge statt bei den Unterlagen des Vorgangs.

## 0.3.19 (2026-11-22)

**Neu**
- Im Chat steht jetzt immer, ob du mit Claude oder mit Codex sprichst: oben unter dem Namen der Sitzung, farbig und mit Symbol (Claude orange, Codex türkis). Das gilt für laufende und für fortgesetzte Sitzungen. Dieselbe Angabe steht unten im Sitzungsmenü (drei Punkte oben rechts), zum Beispiel „Agent: Codex · Konto x1“.
- Neue Sitzung: Der Vault-Ordner ist als Startordner vorgewählt, du kannst sofort auf „Starten“ tippen. Ein anderer Ordner bleibt wie bisher wählbar (zuletzt benutzt, Suche, Durchsuchen). Gilt für Claude und Codex gleich. Welcher Ordner der Vault ist, steht in Einstellungen → Ablage.

**Behoben**
- Der Name des Agenten stand bisher mitten in der kleinen Zeile unter dem Sitzungsnamen und wurde bei langen Ordnernamen abgeschnitten. Deshalb war oft nicht zu erkennen, wer gerade arbeitet.

## 0.3.18 (2026-11-22)

**Behoben**
- Codex: Nach der ersten Antwort ließ sich keine zweite Nachricht senden. Die App meldete, die Sitzung sei am PC in einem Terminal ohne tmux offen, obwohl dort nichts lief. Ursache war eine Änderung in Codex 0.171, die das Gateway auf dem PC falsch gedeutet hat. Das Gateway ist korrigiert und läuft schon, die Sitzung behält jetzt ihre Verbindung zum Fenster, und Nachrichten kommen an.
- Codex-Sitzungen standen nach der ersten Nachricht doppelt in der Liste (einmal als „neu, noch keine Nachrichten“, einmal mit Titel). Jetzt steht jede Sitzung einmal da.

**Neu**
- Dieselbe Codex-Unterhaltung am Rechner und am Handy: Du kannst an beiden Geräten in derselben Unterhaltung weiterschreiben, ohne Übergabe und ohne dass ein Gerät gesperrt wird. Nachrichten vom Handy laufen der Reihe nach, auch wenn Codex gerade arbeitet oder du am PC schon etwas ins Eingabefeld getippt hast.
- Das geht auch für Codex-Unterhaltungen, die am PC in einem Terminal ohne tmux offen sind. Über der Eingabe steht dann „Auch am PC offen (ohne tmux)“. Slash-Befehle und den Live-Bildschirm gibt es dort nicht.

**Geändert**
- Nachrichten an Codex, die mit „ohne tmux“ abgelehnt wurden und noch keine Stunde alt sind, gehen jetzt von selbst hinaus.
- Noch nicht geprüft: das Zusammenspiel mit der geöffneten Codex-App am PC und der Ablauf am iPhone selbst.

## 0.3.17 (2026-11-21)

**Neu**
- Teilen an Relay: Oben im Blatt steht das Ziel „Neue Sitzung“. Relay lädt die Datei hoch und startet einen neuen Agenten im Vault-Ordner. Er bekommt deine Nachricht und die Datei, die Sitzung heißt wie die Datei, und der neue Chat öffnet sich.
- Teilen an Relay: neues Ziel „In Dokumente ablegen“ für Unterlagen, die nicht ins Vault gehören. Ein Agent liest die Datei, schlägt ein bis drei passende Ordner in deinen Dokumenten vor und fragt dich im Chat, wohin sie soll. Erst nach deiner Antwort verschiebt er sie. Er legt keine Ordner an und benennt keine um, ohne dass du zustimmst.
- Einstellungen, Abschnitt „Ablage“: Der Dokumenten-Ordner auf dem PC ist einstellbar (Standard `~/Dokumente/privat/Dokumente`).

**Behoben**
- Eine geteilte Datei landete ungefragt in der zuletzt genutzten Sitzung. Jetzt ist „Neue Sitzung“ vorausgewählt. Eine bestehende Sitzung bekommt die Datei nur noch, wenn du sie antippst.

**Geändert**
- Der Knopf oben rechts im Teilen-Blatt heißt je nach Ziel „Starten“, „Ablegen“ oder „Senden“.

## 0.3.16 (2026-11-12)

**Behoben**
- Die Antwort des Agenten kam im offenen Chat nicht an, wenn die App zwischendurch im Hintergrund war. iOS trennt die Verbindung dort nach kurzer Zeit. Nach dem Wiederverbinden lädt der Chat den Verlauf jetzt nach und liest wieder live mit. Bisher musstest du den Chat schließen und neu öffnen, um die Antwort zu sehen.

**Neu**
- Arbeitet eine Sitzung noch, wenn du Relay verlässt, hält die App die Verbindung bis zu 25 Sekunden. Eine kurze Antwort kommt so noch als Mitteilung „Fertig“ an.
- Abgelehnte Nachrichten gehen nicht mehr unter. Lehnt der PC eine Nachricht ab, weil die Sitzung gerade arbeitet oder am PC ohne tmux läuft, steht im Chat „Wartet: … Geht von selbst hinaus“. Sobald die Sitzung frei ist, sendet Relay sie von selbst, höchstens eine Stunde lang. Danach bleibt sie mit „Wiederholen“, „Bearbeiten“ und „Verwerfen“ stehen.
- In der Sitzungsliste zeigt eine Zeile unter der Sitzung, wenn Nachrichten noch nicht angekommen sind: „1 Nachricht wartet auf die Sitzung“, „1 Nachricht nicht gesendet“ oder „1 Nachricht im Postausgang“.

**Geändert**
- Der Knopf „Am PC beenden und hier fortsetzen…“ ist entfernt. Die so fortgesetzte Sitzung blieb am PC an einer Rückfrage hängen und arbeitete nicht los. Läuft eine Sitzung am PC in einem Terminal ohne tmux, steht über der Eingabe jetzt der Befehl, mit dem du sie am PC neu öffnest (`claude --resume` mit der Kennung der Sitzung). Danach geht es in tmux weiter, und wartende Nachrichten gehen von selbst hinaus.
- Arbeitet die Sitzung beim Senden gerade, heißt die zweite Wahl im Dialog jetzt „Warten“ statt „Abbrechen“. „Trotzdem senden“ bleibt.

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
