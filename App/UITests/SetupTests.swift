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
        if !host.exists { app.swipeUp() }
        XCTAssertTrue(host.waitForExistence(timeout: 5), "Hostfeld fehlt")
        host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields["Port"]
        port.tap(); port.typeText("\u{8}\u{8}" + (env["RELAY_UI_PORT"] ?? "2222"))
        let user = app.textFields["Benutzer"]
        user.tap(); user.typeText(env["RELAY_UI_USER"] ?? NSUserName())
        shot("einrichtung-ausgefuellt")
        dismissKeyboard()
        tap("Verbinden", exact: true)
        XCTAssertTrue(has("API Refactoring", 30), "nach dem Verbinden keine Sitzungsliste")
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
        XCTAssertTrue(has("API Refactoring", 20))
        shot("wieder-verbunden")
    }
}
