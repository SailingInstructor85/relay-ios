# Nachtlog

## Arbeitspaket 1 (Sitzungsliste, Zustandspunkte, Triage)

Gebaut: StateDot, Triage-Streifen (RAM, CPU, Konto-Pillen, "N brauchen dich"), "Weiter (n)" im Chat-Kopf, Alle gelesen, `session_seen` und `seen_at`, Schließen mit 6 s Rückgängig (Bestätigung bei busy), Kontextmenü Umbenennen und Töten, Segment Laufend/Zuletzt, Schalter Hintergrundläufe, Tags (Alias, Kontext, ruht, geschlossen), Fuzzy-Suche mit fetten Treffern, Avatare (Config-Blöcke, sonst Initialen und Hash-Farbe), Offline-Liste mit "Stand vor X Min.", Cloud-Daten (Event `cloud_sessions`, wartende Einträge in der Liste). Reine Logik in RelayCore (Fuzzy, Triage, Avatars, CloudSession) mit 13 neuen Tests.

Entscheidungen: "Zuletzt" zeigt nur beendete, geschlossene und ruhende Sitzungen (ersetzt den Menüschalter "Beendete zeigen"). Der Offline-Cache speichert nur die Antwort ohne Dormant und ohne Hintergrundläufe. "Weiter" nutzt `openChat` (ersetzt den Navigationsstapel statt ihn zu verlängern). Abschnitt "Beendet" heißt jetzt "Sonstige" und erscheint selten. Die Konto-Pillen erscheinen nur bei Konten mit `windows` (bei Martin ohne Pool vermutlich keine).

Risiken: App-Code kompiliert in CI, ist aber nicht auf dem Gerät getestet. Undo-Close im Hintergrund hängt an `beginBackgroundTask` (ca. 30 s). Navigation bei "Weiter" aus dem Chat setzt den Pfad zurück. Cloud-Zeile öffnet die URL in Safari.

Commits: f9d8736 (Code). CI-Lauf 41932819896 grün (core-tests, ipa).

## Arbeitspaket 2 (Chat lesen: Nachrichtenmenü, Links, Dateien, Markdown)

Gebaut: Datei-Chips mit Thumbnails (`file_get` mit `thumb`, höchstens 3 gleichzeitig), Dateiansicht (Bild mit Zoom und Doppeltipp, PDF per PDFKit, Text und Code monospace mit Kopieren, Markdown gerendert, sonst Quick Look; Teilen, Sichern, Pfad kopieren), Cache unter `Caches/relay-files/<hash>-<mtime>` mit Fortschritt. Links: Markdown-Links, `<url>`, nackte URLs im Text tippbar, Dateipfade (absolut, `~/`, relativ zum Sitzungsordner, `:zeile` abgeschnitten) öffnen über `file_info` die Ansicht. Nachrichtenmenü per langem Drücken (Kopieren, Text auswählen, Vorlesen, Links bis 30, Dateien). Markdown als Blöcke (Überschriften, Listen mit Aufgabenkästchen, Zitate, Trennlinien, Tabellen, Codeblöcke mit Kopieren). Werkzeugzeilen mit Pfad tippbar, Marke "Anfang des Gesprächs", Dateisymbole nach Art. Reine Logik in RelayCore (Links, LinkTargets, FileKinds, ToolPaths, ZoomMath, MdBlocks) mit 8 neuen Tests.

Entscheidungen: Auswahl direkt im Chat entfällt (`textSelection` kollidiert mit dem langen Drücken), dafür "Text auswählen" im Menü (UITextView). Vorlesen nutzt vorerst die vorhandene Stimmenwahl von Jarvis (WP6 macht die Einstellungen). Text über 600 KB wird in der Ansicht gekürzt. Dateien über 100 MB werden abgelehnt. Gateway-Fehlertexte (`refused: ...`) erscheinen unverändert.

Risiken: App-Code kompiliert in CI, ist aber nicht auf dem Gerät getestet. Langes Drücken auf eine Zeile kann beim Scrollen selten auslösen. Zoom-Gesten (Pinch plus Ziehen) sind ungetestet. HEIC und SVG hängen von der Gateway-Antwort ab (SVG als Text).

Commits: siehe unten. CI-Lauf Code: 41935202511 grün (core-tests, ipa).
