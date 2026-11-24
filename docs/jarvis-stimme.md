# Jarvis' Stimme: Supertonic 3, Stimme M2

Stand: 2026-11-24, Version 0.4.5. Entschieden von Martin am 24.11.2026 nach den Hörproben: Supertonic 3 mit der Stimme
M2 wird Jarvis' Stimme, auf dem Gerät, ohne Cloud. Diese Notiz hält fest, was davon gebaut ist und was fehlt.

## Was gebaut ist (App, 0.4.5)

- **Zahlen als Wörter** (`SpokenNumbers` in RelayCore, mit Tests). Die Hörproben lasen „1081“ falsch, deshalb bekommt
  eine Stimme wie Supertonic den Text mit ausgeschriebenen Zahlen:
  - Zahlen: „1081“ und „1.081“ werden „eintausendeinundachtzig“, „1.000.000“ wird „eine Million“
  - Datum: „am 24.11.2026“ wird „am vierundzwanzigsten November zweitausendsechsundzwanzig“
  - Uhrzeit: „14:30 Uhr“ wird „vierzehn Uhr dreißig“
  - Ordnungszahl nach Artikel: „der 1. Platz“ wird „der erste Platz“
  - Versionen und Adressen: „0.4.4“ wird „null Punkt vier Punkt vier“
  - Geld und Prozent: „12,50 €“ wird „zwölf Euro fünfzig“, „50 %“ wird „fünfzig Prozent“
  - Kennungen bleiben: Ziffern an Buchstaben („R1“, „M2“) stehen, Nummern mit führender Null oder mehr als neun
    Stellen werden Ziffer für Ziffer gesagt
- Noch **nicht angeschlossen**: Die Apple-Stimme liest Zahlen, Daten und Uhrzeiten selbst richtig, für sie bleibt der
  Text, wie er ist. Die Regeln gelten nur für deutsche Sätze und greifen, sobald Supertonic spricht.

## Was fehlt: iPhone

Supertonic läuft auf dem iPhone über das Swift-Paket speech-swift (soniqo, Apache 2.0), Modul `SupertonicTTS`. Gelesen
am 24.11.2026 (Paketdatei, Quelltext und Doku im Repo):

- **Das Paket verlangt iOS 18.** Die App baut bisher für iOS 17 (`project.yml`, `deploymentTarget`). Ohne Anheben auf
  iOS 18 lässt sich das Paket nicht einbinden. Das ist Martins Entscheidung (Rückfrage R4 vom 24.11.2026).
- Aufruf laut Quelltext: `SupertonicTTSModel.fromPretrained(cacheDir:progressHandler:)`, dann
  `synthesize(text:voice:language:options:)` mit `voice: "M2"`, `language: "de"`. Ergebnis ist Ton als Zahlenreihe
  (mono, 44,1 kHz), kein Streaming. Die App muss ihn selbst abspielen (heute spricht `AVSpeechSynthesizer` direkt).
- Das Modell (rund 400 MB) lädt das Paket beim ersten Benutzen von Hugging Face, Ablage
  `aufklarer/Supertonic-3-CoreML`. Das ist eine für Apple-Geräte umgewandelte Fassung, nicht von Supertone selbst
  veröffentlicht. Die Gewichte stehen unter OpenRAIL-M (Nutzungsauflagen). Danach läuft alles auf dem Gerät.
- Das Paket bringt viele weitere Abhängigkeiten mit (mlx-swift, WhisperKit, hummingbird und andere). Gebraucht wird
  nur `SupertonicTTS` mit `AudioCommon`. Ob die übrigen Bauzeit oder App-Größe erhöhen, zeigt erst ein Build.
- Laut Paket Echtzeitfaktor 0,15 auf dem iPhone 16 Pro. Die deutsche Klangqualität der umgewandelten Fassung ist
  nicht geprüft (die Hörproben entstanden am PC mit der ONNX-Fassung).

Vorschlag für den Bau, sobald iOS 18 freigegeben ist:

1. `project.yml`: `deploymentTarget` iOS 18, Paket speech-swift (fester Stand, zuletzt v0.0.29), Produkt
   `SupertonicTTS` am Ziel Relay.
2. `Voice.swift`: Die Ausgabe in `VoiceIO.say` bekommt eine zweite Maschine neben `AVSpeechSynthesizer`. Deutsche Sätze
   gehen durch `SpokenNumbers.german`, dann an Supertonic, der Ton über `AVAudioPlayerNode`. Die Buchführung
   (`SpeechQueue`, Stopp, `waitUntilSpoken`) bleibt, nur die Kennung des Satzes ändert sich. Scheitert Laden oder
   Sprechen, spricht den Satz die Apple-Stimme. Englische Sätze bleiben bei der Apple-Stimme.
3. `VoicePickerView.swift`: unter „Stimme Deutsch“ der Eintrag „Supertonic 3 (M2)“ mit Hinweis auf den Download und
   einem Knopf zum Laden und Löschen. Die Apple-Stimmen bleiben wählbar. Geladen wird nur, wenn sie gewählt ist.
4. Ein späterer Wechsel des Modells tauscht nur diese zweite Maschine.

## Was fehlt: PC („Hey Jarvis“)

Das liegt im Gateway (`~/relay`, `gateway/src/notifyd/speech_out.py`), nicht in dieser App. Der Nachtbau der App ändert
das Gateway nicht. Zu tun dort:

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
