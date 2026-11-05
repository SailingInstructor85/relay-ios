import XCTest

final class SetupTests: RelayTestCase {
    /// Erster Start: Einrichtung, Verbinden, Host-Schlüssel wird gepinnt.
    func test01_SetupConnectAndPin() {
        launch(prefill: false)
        expect("Relay einrichten", 10)
        shot("einrichtung-leer")
        XCTAssertTrue(has("notifyd setup key"), "Einrichtungsbefehl fehlt")
        tap("Befehl kopieren", soft: true)
        shot("einrichtung-befehl-kopiert")
        // Felder ausfüllen
        let host = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Host'")).firstMatch
        app.swipeUp(); app.swipeUp()
        settle(0.5)
        XCTAssertTrue(host.waitForExistence(timeout: 5), "Hostfeld fehlt")
        func focus(_ e: XCUIElement) {
            for _ in 0..<3 {
                e.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap(); settle(0.6)
                if app.keyboards.count > 0 { return }
                dismissSystemAlerts()
            }
            shot("kein-fokus")
        }
        shot("einrichtung-gescrollt")
        focus(host); host.typeText("127.0.0.1\n"); settle(0.5)
        let port = app.textFields["Port"]
        focus(port); port.typeText("\u{8}\u{8}" + (env["RELAY_UI_PORT"] ?? "2222") + "\n"); settle(0.5)
        shot("einrichtung-port")
        let user = app.textFields["Benutzer"]
        focus(user); user.typeText((env["RELAY_UI_USER"] ?? NSUserName()) + "\n"); settle(0.6)
        shot("einrichtung-ausgefuellt")
        tap("Verbinden", exact: true)
        XCTAssertTrue(has("Wartet auf dich", 30), "nach dem Verbinden keine Sitzungsliste")
        shot("liste-nach-verbinden")
        // Host-Schlüssel gepinnt?
        mainMenu("Einstellungen")
        expect("Gepinnter Host-Schlüssel", 6)
        shot("einstellungen-hostkey")
    }

    /// Verbindung trennen und wieder aufbauen: Pin bleibt, Liste kommt zurück.
    func test02_ReconnectKeepsPin() {
        launchConnected()
        ctl("kick")
        settle(3)
        shot("nach-kick")
        mainMenu("Neu verbinden")
        XCTAssertTrue(has("Wartet auf dich", 20))
        shot("wieder-verbunden")
    }
}
