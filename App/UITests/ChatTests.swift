import XCTest

final class ChatTests: RelayTestCase {
    func test01_OpenChatAndRichContent() {
        launchConnected()
        openSession("API Refactoring")
        settle(1.5)
        shot("chat-ende")
        expect("Zusammenfassung", 4, soft: true)
        expect("Hier der Startcode", 4, soft: true)
        // Kontextkopf
        expect("opus", 3, soft: true)
        app.swipeDown()
        settle(0.5)
        shot("chat-nach-oben-1")
    }

    func test02_ScrollAndPaging() {
        launchConnected()
        openSession("API Refactoring")
        for i in 1...6 {
            app.swipeDown(velocity: .fast)
            if i % 2 == 0 { settle(0.8) }
        }
        shot("chat-gescrollt")
        for _ in 1...10 { app.swipeDown(velocity: .fast) }
        settle(1.5)
        shot("chat-weiter-oben")
        for _ in 1...20 { app.swipeDown(velocity: .fast) }
        settle(2)
        shot("chat-anfang")
        expect("Anfang des Gesprächs", 4, soft: true)
        XCTAssertTrue(mockReceived("transcript", where: { $0["before"] != nil }), "ältere Seite wurde nie geladen")
    }

    func test03_MessageMenuAndLinks() {
        launchConnected()
        openSession("API Refactoring")
        let msg = find("Zusammenfassung")
        XCTAssertNotNil(msg)
        msg?.press(forDuration: 1.2)
        settle(1)
        shot("nachrichtenmenue")
        expect("Kopieren", 3, soft: true)
        expect("Text auswählen", 3, soft: true)
        if tap("Text auswählen", 3, soft: true) {
            settle(1); shot("text-auswaehlen"); tap("Schließen", soft: true)
        } else { app.tap() }
        // Menü mit Links
        find("Zusammenfassung")?.press(forDuration: 1.2)
        settle(1)
        expect("example.com", 3, soft: true)
        shot("nachrichtenmenue-links")
        app.tap()
    }

    func test04_FileViewers() {
        launchConnected()
        openSession("API Refactoring")
        settle(1)
        // Dateichips: README, main.py, Diagramm, Bericht
        if tap("README.md", 5, soft: true) {
            settle(2); shot("datei-markdown")
            tap("Schließen", soft: true)
        }
        if tap("main.py", 5, soft: true) {
            settle(2); shot("datei-code")
            tap("Schließen", soft: true)
        }
        if tap("diagramm.png", 5, soft: true) {
            settle(2); shot("datei-bild")
            app.windows.firstMatch.doubleTap()
            settle(1); shot("datei-bild-zoom")
            tap("Schließen", soft: true)
        }
        if tap("bericht.pdf", 5, soft: true) {
            settle(3); shot("datei-pdf")
            tap("Schließen", soft: true)
        }
        XCTAssertTrue(mockReceived("file_get"))
    }

    func test05_FilePathTap() {
        launchConnected()
        openSession("API Refactoring")
        settle(1)
        shot("pfad-vorher")
        // Pfad im Text
        if let e = find("src/main.py:3") ?? find("/home/dev/workspace/webapp/src/main.py") {
            e.tap(); settle(2); shot("pfad-getippt")
        } else { notes.append("Pfad im Text nicht als Element gefunden") }
        XCTAssertTrue(mockReceived("file_info", timeout: 3), "Pfad-Tipp löst kein file_info aus")
    }

    func test06_ToolRowAndRunning() {
        launchConnected()
        openSession("Bench-Skript reparieren")
        settle(2)
        shot("chat-arbeitet")
        expect("Benchmarks auswerten", 5, soft: true)
        expect("Computing", 3, soft: true)
        // Laufende Aufgaben aufklappen
        tap("Subagent", 2, soft: true)
        settle(1); shot("chat-laufende-aufgaben")
        tapID("chatMenu")
        shot("chat-menue-busy")
        expect("Stoppen", 3)
        app.tap()
    }

    func test07_ChatSearch() {
        launchConnected()
        openSession("API Refactoring")
        tapID("chatMenu")
        tap("Im Verlauf suchen")
        settle(1)
        shot("chat-suche-leer")
        let f = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        f.tap(); f.typeText("Tabelle\n")
        settle(2)
        shot("chat-suche-treffer")
        XCTAssertTrue(mockReceived("transcript_search"))
        // Treffer antippen springt zur Stelle
        if app.cells.count > 0 { app.cells.firstMatch.tap(); settle(2); shot("chat-suche-sprung") }
        f.tap()
    }

    func test08_SearchFromList() {
        launchConnected()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Schritt 5")
        settle(3)
        shot("app-suche-gespraeche")
        // Treffer in einem Gespräch öffnen
        let hits = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Schritt 5'"))
        if hits.count > 0 { hits.firstMatch.tap(); settle(2.5); shot("app-suche-chat-offen") }
    }

    func test09_Summary() {
        launchConnected()
        openSession("API Refactoring")
        tapID("chatMenu")
        tap("Zusammenfassen", soft: true)
        settle(2.5)
        shot("zusammenfassung")
        XCTAssertTrue(mockReceived("speak_summary"))
    }

    func test10_PinMuteFromChat() {
        launchConnected()
        openSession("API Refactoring")
        tapID("chatMenu"); tap("Anheften", soft: true)
        settle(0.5)
        tapID("chatMenu"); tap("Stummschalten", soft: true)
        settle(0.5)
        tapID("chatMenu"); shot("chat-menue-gepinnt")
        expect("Loslösen", 2)
        app.tap()
        XCTAssertTrue(mockReceived("set_pinned"))
    }

    func test11_CloseFromChat() {
        launchConnected()
        openSession("Abrechnung einrichten")
        tapID("chatMenu")
        tap("Sitzung schließen", soft: true)
        settle(2)
        shot("chat-nach-schliessen")
        XCTAssertTrue(mockReceived("close"))
    }
}
