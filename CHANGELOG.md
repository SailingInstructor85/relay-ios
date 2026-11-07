# Changelog

Versionen der iPhone-App Relay, neueste oben. Aus dem obersten Abschnitt entstehen der Release-Text auf GitHub und die Versionsbeschreibung in SideStore. Ältere Versionen stehen in den GitHub-Releases.

## 0.3.5 (2026-11-07)

**Neu**
- Lesemodus im Chat: Der Knopf oben rechts (Pfeile nach außen) blendet Navigationsleiste, Eingabezeile und Tastatur aus, der Verlauf nutzt den ganzen Bildschirm. Neue Nachrichten laufen weiter ein, der Bildschirm bleibt wie beim Zuschauen an. Der kleine Knopf oben rechts bringt die normale Ansicht zurück.
- Tastatur im Chat schließen: Ein Knopf in der Leiste über der Tastatur, ein Tipp in den Verlauf oder Wischen nach unten schließt sie. Getippter Text und ein laufendes Diktat bleiben erhalten.

**Geändert**
- Sitzungsübergabe Handy/PC entfernt: kein „Sitzung übernehmen“, keine Rückfrage „Sitzung vom PC übernehmen?“ vor dem Senden, keine Tags „Am Handy“ und „Am PC“. Handy und PC tippen wieder wie bis 0.3.3 abwechselnd in dieselbe Sitzung. Im Gateway sind Schreibschutz, rote Statuszeile und Strg-b H weg. „Alle Sitzungen beenden“ und das Senden in Sitzungen am PC ohne tmux bleiben.

Hinweis: Damit der Rückbau auch im Gateway greift, muss notifyd einmal neu gestartet werden. Die App läuft auch mit dem älteren Gateway.
