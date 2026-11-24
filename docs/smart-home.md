# Smart Home: Fernseher über den PC schalten

Stand: 2026-11-24, Version 0.4.6. Im Tab „Mehr“ steht der Punkt „Smart Home“ mit dem Abschnitt „Fernseher“:
„Fernseher einschalten“, „HDMI 2 aktivieren“, „Fernsehen“ und „Fernseher ausschalten“.

## Wie es gedacht ist

Die App schaltet den Fernseher nicht selbst. Sie bittet das Gateway am PC um eine von vier fest hinterlegten Aktionen,
das Gateway startet dafür ein Skript, das am PC liegt und dort geprüft ist, und meldet dessen Ausgabe zurück. Die App
zeigt diese Rückmeldung oben auf der Seite („Umgeschaltet auf HDMI 2“, „Fernseher ausgeschaltet.“ oder den
Fehlertext). Ein kalter Fernseher braucht bis zu 3 Minuten, so lange wartet die App (200 Sekunden) und zeigt, was läuft.

Vom Handy kommen keine freien Befehle: Die App schickt nur den Namen des Geräts und der Aktion. Welches Skript dazu
gehört, steht ausschließlich am PC.

## Was gebaut ist (App)

- Seite „Smart Home“ (`SmartHomeView.swift`), Zeile im Tab „Mehr“, Ziel `smartHome`
- Aktionen, Parameter und Texte in RelayCore (`SmartHome.swift`, mit Tests)
- UI-Test gegen das Test-Gateway (`test10_SmartHomeFernseher`)

## Was fehlt (Gateway)

Der Aufruf `smart_home` ist im Gateway noch nicht vorhanden. Bis dahin zeigt die App bei jeder Aktion: „Das Gateway
auf dem PC kann den Fernseher noch nicht schalten.“ Das Gateway liegt in einem anderen Projekt und wird dort gebaut.

Vertrag für das Gateway:

```
rpc smart_home {"device": "tv", "action": "on" | "off" | "hdmi2" | "tv"}
  → {"ok": true|false, "text": "<Ausgabe des Skripts, letzte Zeilen>"}
```

- Nur diese vier Aktionen für `device: "tv"` annehmen, alles andere mit einem Fehler ablehnen (`bad action`).
- Die Zuordnung Aktion → Skript mit festen Argumenten steht am PC (Konfiguration des Gateways, etwa ein Block
  `smart_home:`). Nichts aus der Anfrage geht in eine Befehlszeile. Aufruf ohne Shell, als Liste von Argumenten.
- `hdmi2` und `tv` rufen das vorhandene Eingangs-Skript mit dem passenden Argument (es schaltet den Fernseher vorher
  ein), `off` das Ausschalt-Skript. Für `on` gibt es noch kein eigenes Skript: entweder das Eingangs-Skript um einen
  Aufruf erweitern, der nur einschaltet, oder `on` wie `hdmi2` behandeln. Das ist am PC zu entscheiden.
- Laufzeit bis zu 3 Minuten: das Skript mit Zeitgrenze (etwa 190 Sekunden) starten und nicht die Ereignisschleife des
  Gateways blockieren. `ok` ist der Rückgabewert des Skripts, `text` seine letzten Ausgabezeilen.
- Zwei Aufrufe gleichzeitig vermeiden (der zweite wartet oder wird mit „läuft schon“ abgelehnt).

Sobald das Gateway den Aufruf kennt, ist in der App nichts mehr zu tun.

## Grenzen

- Der AV-Receiver lässt sich so nicht mitschalten (am PC gibt es kein HDMI-CEC).
- Ohne Verbindung zum PC sind die Zeilen ausgegraut.
