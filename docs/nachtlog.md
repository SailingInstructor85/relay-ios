# Nachtlog

## Arbeitspaket 1 (Sitzungsliste, Zustandspunkte, Triage)

Gebaut: StateDot, Triage-Streifen (RAM, CPU, Konto-Pillen, "N brauchen dich"), "Weiter (n)" im Chat-Kopf, Alle gelesen, `session_seen` und `seen_at`, Schließen mit 6 s Rückgängig (Bestätigung bei busy), Kontextmenü Umbenennen und Töten, Segment Laufend/Zuletzt, Schalter Hintergrundläufe, Tags (Alias, Kontext, ruht, geschlossen), Fuzzy-Suche mit fetten Treffern, Avatare (Config-Blöcke, sonst Initialen und Hash-Farbe), Offline-Liste mit "Stand vor X Min.", Cloud-Daten (Event `cloud_sessions`, wartende Einträge in der Liste). Reine Logik in RelayCore (Fuzzy, Triage, Avatars, CloudSession) mit 13 neuen Tests.

Entscheidungen: "Zuletzt" zeigt nur beendete, geschlossene und ruhende Sitzungen (ersetzt den Menüschalter "Beendete zeigen"). Der Offline-Cache speichert nur die Antwort ohne Dormant und ohne Hintergrundläufe. "Weiter" nutzt `openChat` (ersetzt den Navigationsstapel statt ihn zu verlängern). Abschnitt "Beendet" heißt jetzt "Sonstige" und erscheint selten. Die Konto-Pillen erscheinen nur bei Konten mit `windows` (bei Martin ohne Pool vermutlich keine).

Risiken: App-Code kompiliert in CI, ist aber nicht auf dem Gerät getestet. Undo-Close im Hintergrund hängt an `beginBackgroundTask` (ca. 30 s). Navigation bei "Weiter" aus dem Chat setzt den Pfad zurück. Cloud-Zeile öffnet die URL in Safari.

Commits: f9d8736 (Code). CI-Lauf 41932819896 grün (core-tests, ipa).
