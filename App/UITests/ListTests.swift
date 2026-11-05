import XCTest

final class ListTests: RelayTestCase {
    func test01_SectionsAndTriage() {
        launchConnected()
        settle(2)
        shot("liste-oben")
        expect("Wartet auf dich")
        expect("Arbeitet")
        expect("Bereit")
        expect("Abrechnung einrichten")
        expect("Bench-Skript reparieren")
        expect("Datenbank migrieren") // asks: true
        expect("brauch", 6, soft: true) // Triage "N brauchen dich"
        expect("RAM", 8, soft: true)
        app.swipeUp()
        shot("liste-unten")
        app.swipeDown()
    }

    func test02_SearchAndTriage() {
        launchConnected()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("api")
        settle(1.5)
        shot("suche-api")
        search.clearText()
        search.typeText("Frage 3")
        settle(2.5)
        shot("suche-gespraeche")
        expect("In Gesprächen", 6, soft: true)
        search.clearText()
        search.typeText("zzzzzz")
        settle(2)
        shot("suche-leer")
        if app.buttons["Abbrechen"].exists { app.buttons["Abbrechen"].tap() }
    }

    func test03_PinMuteSwipe() {
        launchConnected()
        let row = find("API Refactoring")!
        row.swipeRight()
        settle(0.6)
        shot("swipe-rechts")
        tap("Pin", soft: true)
        settle(0.8)
        shot("angepinnt")
        find("API Refactoring")?.swipeRight()
        settle(0.5)
        tap("Stumm", soft: true)
        settle(0.8)
        shot("stumm")
        // Kontextmenü
        find("API Refactoring")?.press(forDuration: 1.2)
        settle(0.8)
        shot("kontextmenue")
        expect("Anheften", 3, soft: true)
        expect("Loslösen", 3, soft: true)
        app.tap()
    }

    func test04_CloseAndUndo() {
        launchConnected()
        find("Datenbank migrieren")?.swipeLeft()
        settle(0.6)
        shot("swipe-links")
        tap("Schließen", soft: true)
        settle(1)
        shot("geschlossen-mit-rueckgaengig")
        expect("Sitzung geschlossen.", 4)
        tap("Rückgängig", exact: true, soft: true)
        settle(1.5)
        shot("nach-rueckgaengig")
        expect("Datenbank migrieren")
    }

    func test05_CloseBusyAsksConfirm() {
        launchConnected()
        find("Bench-Skript reparieren")?.swipeLeft()
        settle(0.5)
        tap("Schließen", soft: true)
        settle(1)
        shot("busy-schliessen-bestaetigung")
        expect("Stoppen und schließen", 3)
        tap("Abbrechen", soft: true)
    }

    func test06_RenameViaContextMenu() {
        launchConnected()
        find("API Refactoring")?.press(forDuration: 1.2)
        settle(0.8)
        if tap("Umbenennen", soft: true) {
            shot("umbenennen-dialog")
            let f = app.alerts.textFields.firstMatch
            if f.exists { f.typeText("Neuer Name") }
            tap("Umbenennen", exact: true, soft: true)
            settle(1)
        }
        shot("nach-umbenennen")
    }

    func test07_RecentAndBackground() {
        launchConnected()
        tap("Zuletzt", exact: true)
        settle(2)
        shot("zuletzt")
        expect("Altes Experiment", 6)
        expect("Logs aufraeumen", 3, soft: true)
        tap("Laufend", exact: true)
        settle(1)
        mainMenu("Hintergrundläufe")
        settle(2)
        tap("Zuletzt", exact: true, soft: true)
        settle(2)
        shot("zuletzt-mit-hintergrund")
        expect("Nachtlauf Index", 4, soft: true)
    }

    func test08_ReopenDormant() {
        launchConnected()
        tap("Zuletzt", exact: true)
        settle(2)
        tap("Altes Experiment", 6)
        settle(2)
        shot("beendete-sitzung-chat")
        tapID("chatMenu")
        settle(0.6)
        shot("beendet-menue")
        tap("Wieder öffnen", soft: true)
        settle(2)
        shot("wieder-geoeffnet")
        XCTAssertTrue(mockReceived("reopen"))
    }

    func test09_LiveEvents() {
        launchConnected()
        ctl("trigger_finish_busy")
        settle(3)
        shot("live-busy-fertig")
        ctl("trigger_new_input")
        settle(3)
        shot("live-neue-frage")
        expect("Darf ich die alte Route", 5, soft: true)
        ctl("trigger_end_session")
        settle(3)
        shot("live-sitzung-beendet")
        ctl("trigger_desktop_sleep")
        settle(3)
        shot("live-desktop-schlaeft")
    }

    func test10_OfflineList() {
        launchConnected()
        ctl("offline")
        ctl("kick")
        settle(5)
        shot("offline-liste")
        expect("API Refactoring")
        ctlRemove("offline")
        tap("Erneut", soft: true)
        settle(8)
        shot("offline-wieder-online")
    }
}

extension XCUIElement {
    func clearText() {
        guard let s = value as? String, !s.isEmpty else { return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: s.count))
    }
}
