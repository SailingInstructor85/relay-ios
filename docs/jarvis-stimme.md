# Jarvis' Stimme: Supertonic 3, Stimme M2

Stand: 2026-11-26, Version 0.4.12. Entschieden von Martin am 24.11.2026 nach den Hörproben: Supertonic 3 mit der Stimme
M2 wird Jarvis' Stimme, auf dem Gerät, ohne Cloud. Am iPhone ist das seit 0.4.6 gebaut, am PC („Hey Jarvis“) fehlt es
noch. Auf dem iPhone gehört ist die Stimme noch nicht: Swift läuft am Bau-PC nicht, geprüft hat nur die CI.

## iPhone: so schaltest du die Stimme ein

1. Einstellungen → „Sprache und Stimme“ → „Stimme Deutsch“ → „Supertonic 3 (M2) · auf dem Gerät“ wählen.
2. Darunter erscheint eine Zeile mit „Modell laden“. Das Modell hat rund 400 MB und kommt einmalig von Hugging Face.
   Die Zeile zeigt den Fortschritt, „Abbrechen“ hält an, ein neuer Versuch lädt nur, was noch fehlt.
3. „Testen“ spricht den Probesatz. Beim ersten Mal übersetzt iOS das Modell für den Chip, das dauert spürbar länger.
4. „Modell löschen“ gibt den Platz wieder frei, Jarvis spricht dann wieder mit der Apple-Stimme.

Die Apple-Stimme bleibt voreingestellt („Beste vorhandene“), bis du Supertonic wählst.

## iPhone: wie es arbeitet

- Deutsche Sätze spricht Supertonic, englische die Apple-Stimme (Einstellung „Stimme Englisch“). Die Sätze laufen
  der Reihe nach, damit die Reihenfolge stimmt, obwohl Supertonic den Ton erst berechnen muss. Den nächsten Satz
  berechnet die App schon, während der laufende spielt.
- Vor der Ausgabe werden Zahlen, Daten und Uhrzeiten in Wörter gewandelt (`SpokenNumbers`: „1081“ wird
  „eintausendeinundachtzig“, „14:30 Uhr“ wird „vierzehn Uhr dreißig“). Markdown, Code und Links fallen wie bisher weg.
- Seit 0.4.8 gibt es dazu eine Ausspracheliste (`SpokenWords` in RelayCore): Wörter, die Supertonic falsch liest,
  bekommt die Stimme in einer Schreibweise, die sie richtig spricht. Erster Eintrag: „Chief“ wird als „Tschief“
  gesprochen (ohne Eintrag liest die Stimme das „Ch“ deutsch). Nur ganze Wörter, Groß- und Kleinschreibung egal, ein
  angehängtes „s“ bleibt. Ein neues Wort ist eine Zeile in der Liste und ein Satz in `SpokenWordsTests`. Eingetragen
  wird nur, was eine Hörprobe bestanden hat. „Zion“ steht noch aus (Hörprobe durch Martin, siehe `docs/nachtlog.md`,
  Nachtbau vom 25.11.2026).
- Das Modell liegt nicht in der App. Es wird erst auf deinen Knopfdruck geladen und erst in den Speicher geholt, wenn
  Jarvis sprechen soll (beim Start der Aufnahme und beim Beginn einer Antwort). Bis es bereit ist, spricht die
  Apple-Stimme. Bei einer Speicherwarnung von iOS gibt die App das Modell frei.
- Seit 0.4.11: Scheitert Supertonic bei einem Satz, lädt die App das Modell frisch für den Prozessor und versucht
  den Satz noch einmal. Erst wenn auch das scheitert, spricht die Apple-Stimme ihn. Nach zwei Sätzen in Folge, bei
  denen beide Versuche scheitern, ruht Supertonic. Bis 0.4.11 galt das bis zum nächsten Start der App oder bis zu
  „Erneut laden“. Seit 0.4.12 ruht es nur für den Rest der Antwort, siehe unten.
- Seit 0.4.11: Im Vordergrund rechnet Supertonic mit allem, was das iPhone hat (auch Grafikchip). Im Hintergrund
  (Bildschirm gesperrt, andere App vorn) verbietet iOS den Grafikchip, dort rechnet nur der Prozessor. Kommt die
  App wieder nach vorn, lädt das Modell gleich wieder für den schnellen Weg (`VoiceCompute` in RelayCore).
- Seit 0.4.11: Nach dem Laden rechnet das Modell einmal „Hallo.“, ohne es abzuspielen. Der erste Satz nach dem
  Laden braucht sonst ein Vielfaches (gemessen 7,35 s für 37 Zeichen, danach rund 0,5 s).
- Seit 0.4.11: Bekommt die App im Hintergrund die Tonausgabe nicht, hält sie die Sätze zurück, statt sie stumm
  durchlaufen zu lassen, und spricht sie, sobald sie wieder vorn ist (höchstens zwei Minuten später, `HeldSpeech`
  in RelayCore, gilt für beide Stimmen). Damit es dazu selten kommt, bleibt der Bildschirm an, solange eine
  gesprochene Frage in Jarvis auf ihre Antwort wartet, die vorgelesen werden soll.
- Seit 0.4.12: Supertonic schaltet sich nicht mehr dauerhaft ab. Nach zwei ganz gescheiterten Sätzen spricht die
  Apple-Stimme den Rest der Antwort. Die nächste Antwort, die nächste Aufnahme, „Testen“, ein „Vorlesen“ oder die
  Rückkehr der App in den Vordergrund lädt das Modell frisch und beginnt von vorn (`VoiceCompute.revive`,
  `SupertonicStore.wake`). Die Stimmenauswahl zeigt die Pause an. Einen Fehler zeigt sie erst, wenn auch das
  Neuladen scheitert, und selbst dann versucht es die nächste Antwort wieder.
- Seit 0.4.12: Die App berechnet den Ton aller schon bekannten Sätze einer Antwort voraus (bis 30 Sätze), nicht
  nur den des nächsten. Sperrt sich das iPhone mitten in der Antwort, liegt der Rest meist schon fertig da. Womit
  gerechnet wird (Grafikchip oder Prozessor), entscheidet sich erst, wenn ein Satz an der Reihe ist. So scheitert
  ein vorausgeplanter Satz nicht erst auf dem Grafikchip, wenn die App inzwischen im Hintergrund ist.
- Seit 0.4.12: Während Jarvis eine Antwort vorliest, bleibt der Bildschirm an (höchstens zehn Minuten, wie bei einer
  Aufnahme). Das gilt nur in Jarvis, im Fahrmodus bleibt er ohnehin an. Drückst du die Seitentaste, spricht
  Jarvis im Hintergrund weiter.
- „Tempo“ gilt auch für Supertonic.
- Es gilt für Jarvis, den Sprachmodus und überall, wo die App Antworten satzweise vorliest. Seit 0.4.12 auch für
  „Vorlesen auf Knopfdruck“ (`SpeechOut`: Lautsprecher unter einer Nachricht, „Frage vorlesen“, Rückfragen,
  Meldungen), mit Pause und Weiter. Dort wartet der erste Satz, bis das Modell geladen ist, statt mit der
  Apple-Stimme zu beginnen. Ohne Supertonic liest dort wie bisher die Apple-Stimme den Text am Stück.
- Im Protokoll der App (am PC `notifyd phone log`) stehen für die ersten Sätze nach dem Start Länge, Rechenzeit und
  Echtzeitfaktor, dazu die Ladezeit des Modells. Seit 0.4.12 getrennt gezählt für den schnellen Weg und den Prozessor
  (Zusatz „, Prozessor“, im Hintergrund „, App im Hintergrund“, nach einem ersten Fehlversuch „, mit Neuladen“).
- Seit 0.4.12 steht jeder Rückfall im Protokoll: „Apple-Stimme statt Supertonic (App vorn oder im Hintergrund)“,
  die ersten 40 Zeichen des Satzes und der Grund (bei „Vorlesen“ mit dem Vorsatz „Vorlesen:“). Diese Einträge
  warten ohne Verbindung in einer Datei auf dem iPhone (`kept-log.json`, höchstens 60) und gehen bei der nächsten
  Verbindung an den PC. Damit stehen erstmals Satzanfänge im Protokoll, sonst weiter keine Sätze.

## iPhone: was dahinter steckt

- Die Rechenschritte stammen aus dem Swift-Paket speech-swift (soniqo, Apache 2.0), Modul `SupertonicTTS`, Stand
  v0.0.29. Übernommen sind nur dessen fünf Quelldateien (`App/Sources/Supertonic`), nicht das Paket. Das Paket hätte
  iOS 18 und viele weitere Abhängigkeiten verlangt (mlx-swift, WhisperKit, hummingbird und andere). So bleibt die App
  bei iOS 17 und wird nicht größer. Martin hatte iOS 18 und das Paket am 24.11.2026 freigegeben (Rückfrage R4), nötig
  war beides nicht. Ob das Modell auf iOS 17 läuft, ist nicht geprüft. Läuft es nicht, spricht die Apple-Stimme.
- Das Modell kommt aus der Hugging-Face-Ablage `aufklarer/Supertonic-3-CoreML`. Das ist eine für Apple-Geräte
  umgewandelte Fassung, nicht von Supertone selbst veröffentlicht. Die Gewichte stehen unter OpenRAIL-M. Geladen
  werden nur die vier Modellteile, zwei Tabellen und die Stimme M2. Die Dateiliste des Servers gilt als fremd: nur
  erwartete Pfade, nichts außerhalb des Modellordners, Obergrenze 1,5 GB, Größe jeder Datei wird nach dem Laden
  geprüft (`VoiceModel` in RelayCore, mit Tests). Der Stand der Ablage ist nicht festgenagelt (Zweig `main`).
- Ein späterer Wechsel des Modells tauscht `VoiceModel`, den Ordner `App/Sources/Supertonic` und die Zeile in der
  Stimmenauswahl. Die Sprechkette in `Voice.swift` bleibt.

## Stumme Antwort am 25.11.2026: was passiert ist

Messung aus den Protokollen der App am PC (`notifyd phone log` und Nutzungsprotokoll), Version 0.4.7:

- 23:33:03 Frage diktiert. Die Antwort des Chiefs brauchte 72,5 s.
- 23:33:29 Die App geht in den Hintergrund (das iPhone sperrte sich beim Warten, die Verbindung blieb gehalten).
- 23:34:12 Die Antwort kommt. Supertonic scheitert bei zwei Sätzen mit „Unable to compute the prediction using ML
  Program“. Darunter steht der eigentliche Grund: „GPU sync execute failed: Insufficient Permission (to submit GPU
  work from background)“. Das Modell war also nicht kaputt, iOS verweigert im Hintergrund den Grafikchip.
- 23:34:16 Die Apple-Stimme sollte einspringen, bekam aber die Tonausgabe nicht: zehnmal „audio nicht übernommen“
  (Fehler von iOS beim Aktivieren der Audiositzung aus dem Hintergrund). Alle Sätze liefen stumm durch.
- 23:34:21 Die App ist wieder vorn, da war die Antwort schon „vorgelesen“.
- Folge: Nach den zwei Fehlern ruhte Supertonic bis zum nächsten Start der App.

Was 0.4.11 dagegen tut, steht oben unter „wie es arbeitet“. Nicht behebbar ist, dass eine App im Hintergrund keine
Tonausgabe neu beginnen darf. Läuft das Vorlesen schon, wenn sich das iPhone sperrt, spielt es weiter.

## Stimmwechsel mitten in der Antwort am 26.11.2026

Martin meldete mit 0.4.7: Ab „Beides kommt ins Relay-Backlog“ sprach die Apple-Stimme, danach dauerhaft. Beleg im
Protokoll: 11:37:21 App im Hintergrund, direkt danach zwei „Satz gescheitert“ mit dem Grafikchip-Fehler, die Antworten
danach ohne Supertonic. Dasselbe um 11:50. Ursachen: Rechnen auf dem Grafikchip im Hintergrund (seit 0.4.11 behoben)
und das dauerhafte Ruhen nach zwei Fehlern (seit 0.4.12 behoben). Martins Ziel (26.11.): Eine begonnene Antwort wird
immer mit Supertonic zu Ende gesprochen, auch wenn sich der Bildschirm sperrt.

## iPhone: was noch zu prüfen ist

- Seit 0.4.12: Prüftext aus dem Backlog als Jarvis-Antwort, nach dem zweiten Satz den Bildschirm sperren. Erwartet:
  alle Sätze in M2, im Protokoll kein „Satz gescheitert“ und keine Zeile „Apple-Stimme statt Supertonic“. Danach
  eine weitere Frage: wieder M2. Dazu der Echtzeitfaktor in den Zeilen mit „, Prozessor“: Liegt er über 1,
  entstehen im Hintergrund Pausen zwischen Sätzen, die beim Sperren noch nicht berechnet waren.
- Seit 0.4.12: Pause und Weiter beim „Vorlesen“ mit Supertonic (der erzeugte Ton hält an der Stelle an).
- Offen: Solange das Modell nach dem Start der App noch lädt, sprechen in Jarvis die ersten Sätze mit der
  Apple-Stimme (steht dann als Rückfall im Protokoll). Nach einer Speicherwarnung von iOS ebenso.

- Hörprobe am Gerät: Klang der umgewandelten Fassung (die Hörproben vom 24.11. entstanden am PC mit der ONNX-Fassung),
  Pausen zwischen den Sätzen, Wechsel zwischen deutscher und englischer Stimme.
- Echtzeitfaktor und Ladezeit auf dem iPhone 16 Pro (Protokoll, siehe oben). Laut Paket 0,15.
- Verhalten bei Bluetooth und CarPlay, beim Wechsel des Audiowegs und im Gesprächsmodus (Zuhören direkt nach der
  Antwort).
- Seit 0.4.11: Rechenzeit auf dem Prozessor (im Protokoll steht hinter der Zeile „, Prozessor“), Dauer des Umladens
  beim Wechsel zwischen Hintergrund und Vordergrund, und ob das Aufwärmen mit „Hallo.“ den ersten echten Satz
  wirklich beschleunigt (die Graphen arbeiten mit wechselnder Länge, belegt ist die Wirkung nicht).
- Download über Mobilfunk ist nicht gesperrt. Wer das nicht will, lädt im WLAN.

## Was fehlt: PC („Hey Jarvis“)

Das liegt im Gateway (`gateway/src/notifyd/speech_out.py`), nicht in dieser App. Der Nachtbau der App ändert das
Gateway nicht. Zu tun dort:

- Deutsch mit Supertonic 3 M2 statt Piper Thorsten. Die ONNX-Dateien (`onnx/`, rund 390 MB) und
  `voice_styles/M2.json` liegen in `~/.cache/supertonic3` und gehören für den Dienst nach
  `~/.local/share/notifyd/tts/supertonic3`, Pfad per Umgebungsvariable wie bei Piper (`NOTIFYD_PIPER_DE`), etwa
  `NOTIFYD_SUPERTONIC`.
- `speech_out.py` spricht heute alles über sherpa-onnx (`_load`, `speak`). Supertonic braucht den eigenen Ablauf aus
  vier ONNX-Modellen (Dauer, Text, Vektor, Vocoder), wie er für die Hörproben benutzt wurde. Piper Thorsten bleibt
  Rückfall, wenn die Dateien fehlen oder die Ausgabe scheitert. Englisch bleibt.
- Zahlen vor der Ausgabe in Wörter wandeln, nach denselben Regeln wie `SpokenNumbers` (die Testfälle in
  `RelayCore/Tests/RelayCoreTests/SpokenNumbersTests.swift` taugen als Vorlage).
- Prüfen: Testsatz als WAV erzeugen, per Whisper zurücklesen, Echtzeitfaktor messen.

Stand 25.11.2026: Supertonic 3 M2 und die Zahlenwandlung laufen am PC inzwischen (Gateway, `supertonic.py`,
`spoken_numbers.py`). Es fehlt dort die Ausspracheliste. Sie gehört mit derselben Liste und denselben Regeln wie
`SpokenWords` in ein Modul `spoken_words.py`, aufgerufen vor `spoken_numbers.german`. Ein fertiger, an einer Kopie
getesteter Patch liegt am Bau-PC neben den Hörproben (Ort im Nachtlog).
