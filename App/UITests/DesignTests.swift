import XCTest

/// Bilder der Hauptbildschirme für den Umbau der Oberfläche. Die Tests öffnen nur und hängen Bilder an (`shot`), sie
/// prüfen kaum etwas. In der CI laufen sie als eigener Teil „design“; die Bilder liegen danach im Artefakt
/// `simulator-results-design` unter `out/shots` (Name: `DesignTests__<Test>__DesignTests-<Nr>-<Name>.png`).
/// Für einen schnellen Lauf nur dieser Klasse: `DesignTests/test01_Sitzungsliste` usw. in `testing/only.txt` eintragen.
///
/// Farbschema: Die App folgt sonst dem System. Im Testmodus erzwingt die Startumgebung `RELAY_UI_SCHEME`
/// (`launch(scheme:)`, in der App `UITestMode.colorScheme` mit `preferredColorScheme`) dunkel oder hell. Die Tests
/// 01 bis 03 laufen dunkel, Test 04 nimmt dieselben Bildschirme hell auf. Die Tests 05 und 06 zeigen die Tabs Heute,
/// Dein Zug, Posteingang und Mehr dunkel und hell.
final class DesignTests: RelayTestCase {
    static let session = "API Refactoring"

    private func sessionList(_ prefix: String) {
        showSessions()
        settle(2)
        shot(prefix + "sitzungsliste")
        app.swipeUp()
        settle(0.8)
        shot(prefix + "sitzungsliste-unten")
        app.swipeDown()
        settle(0.5)
    }

    private func chat(_ prefix: String) {
        openSession(Self.session)
        settle(1.5)
        shot(prefix + "chat")
        // Eingabeleiste mit offener Tastatur und Text
        typeInto("chatInput", "Bitte fasse den Stand zusammen")
        settle(0.8)
        shot(prefix + "chat-tastatur")
        // Befehlsmenü an der Eingabeleiste (ersetzt die frühere Chipzeile)
        if id("commandMenu").waitForExistence(timeout: 3) {
            id("commandMenu").tap()
            settle(1)
            shot(prefix + "chat-befehlsmenue")
            if !tap("Tastatur ausblenden", 2, soft: true) { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap() }
            settle(0.8)
        } else {
            notes.append("Befehlsmenü (commandMenu) fehlt")
        }
        shot(prefix + "chat-eingabeleiste")
        // Vorschlagsliste beim Tippen von „/“
        let field = id("chatInput")
        if field.exists { field.clearText(); field.typeText("/") }
        settle(1)
        shot(prefix + "chat-slash-vorschlag")
        back()
        settle(0.8)
    }

    /// Das frühere Hauptmenü: die Seite im Tab „Mehr“.
    private func menu(_ prefix: String) {
        openMainMenu()
        settle(1)
        shot(prefix + "mehr")
        app.swipeUp()
        settle(0.6)
        shot(prefix + "mehr-unten")
        closeMainMenu()
    }

    /// Die neuen Tabs: Heute, Dein Zug (mit Rückfrage und Freigabe aus dem Mock), Posteingang, Mehr.
    private func tabs(_ prefix: String) {
        ctl("trigger_rueckfrage")
        ctl("trigger_send_request")
        settle(3)
        showTab(Self.tabToday)
        settle(1.5)
        shot(prefix + "heute")
        app.swipeUp()
        settle(0.8)
        shot(prefix + "heute-unten")
        showTab(Self.tabYourTurn)
        settle(1)
        shot(prefix + "deinzug")
        app.swipeUp()
        settle(0.8)
        shot(prefix + "deinzug-unten")
        showTab(Self.tabInbox)
        settle(0.8)
        shot(prefix + "posteingang")
        showTab(Self.tabMore)
        settle(0.8)
        shot(prefix + "mehr-tab")
        showSessions()
    }

    func test01_Sitzungsliste() {
        launchConnected(scheme: "dark")
        // Die Kennung selbst muss da sein (launchConnected nimmt notfalls noch den alten Starttext).
        XCTAssertTrue(id(Self.homeReadyID).exists, "Kennung homeReady fehlt auf dem Startbildschirm")
        sessionList("dunkel-")
    }

    func test02_ChatMitEingabeleiste() {
        launchConnected(scheme: "dark")
        chat("dunkel-")
    }

    func test03_Hauptmenue() {
        launchConnected(scheme: "dark")
        menu("dunkel-")
    }

    func test04_Hell() {
        launchConnected(scheme: "light")
        sessionList("hell-")
        chat("hell-")
        menu("hell-")
    }

    func test05_TabsDunkel() {
        launchConnected(scheme: "dark")
        tabs("dunkel-")
    }

    func test06_TabsHell() {
        launchConnected(scheme: "light")
        tabs("hell-")
    }
}
