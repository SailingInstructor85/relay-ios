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
        for _ in 1...40 { if has("Ältere Nachrichten laden", 0.2) { break }; app.swipeDown(velocity: .fast) }
        settle(1)
        shot("chat-weiter-oben")
        for _ in 1..<4 where tap("Ältere Nachrichten laden", 2, soft: true) {
            settle(1.5)
            for _ in 1...30 { if has("Anfang des Gesprächs", 0.2) || has("Ältere Nachrichten laden", 0.2) { break }; app.swipeDown(velocity: .fast) }
        }
        shot("chat-anfang")
        expect("Anfang des Gesprächs", 4, soft: true)
        XCTAssertTrue(mockReceived("transcript", where: { $0["before"] != nil }), "ältere Seite wurde nie geladen")
    }

    func test03_MessageMenuAndLinks() {
        launchConnected()
        openSession("API Refactoring")
        revealChat("Zusammenfassung")
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
        revealChat("Zusammenfassung")
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
        if revealChat("README.md") && tap("README.md", 5, soft: true) {
            settle(2); shot("datei-markdown")
            tap("Schließen", soft: true)
        }
        if revealChat("main.py") && tap("main.py", 5, soft: true) {
            settle(2); shot("datei-code")
            tap("Schließen", soft: true)
        }
        if revealChat("diagramm.png") && tap("diagramm.png", 5, soft: true) {
            settle(2); shot("datei-bild")
            app.windows.firstMatch.doubleTap()
            settle(1); shot("datei-bild-zoom")
            tap("Schließen", soft: true)
        }
        if revealChat("bericht.pdf") && tap("bericht.pdf", 5, soft: true) {
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
        revealChat("Read · README.md")
        if let e = find("Read · README.md") {
            e.tap(); settle(2); shot("werkzeugzeile-pfad-getippt"); tap("Schließen", soft: true)
        } else { notes.append("Werkzeugzeile mit Pfad nicht gefunden") }
        revealChat("src/main.py")
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

    func test13_DeskTerminalReadOnly() {
        // Die Sitzung läuft am PC in einem Terminal ohne tmux: Hinweis über der Eingabe (mit dem Befehl für den PC), Symbol
        // „Am PC offen“ im Kopf, die Nachricht bleibt im Postausgang. Den Umzug vom Handy aus gibt es seit 0.3.16 nicht mehr.
        launchConnected()
        openSession("Skript ohne tmux")
        XCTAssertTrue(id("deskHint").waitForExistence(timeout: 5))
        XCTAssertTrue(id("pcOpen").exists)
        XCTAssertTrue(id("deskHint").label.contains("claude --resume"), "Hinweis nennt den Befehl für den PC nicht: \(id("deskHint").label)")
        typeInto("chatInput", "Bitte Status melden")
        tapID("chatSend")
        settle(1.5)
        shot("ohne-tmux-abgelehnt")
        expect("Terminal ohne tmux offen", 5)
        XCTAssertTrue(mockReceived("send", where: { ($0["text"] as? String) == "Bitte Status melden" && $0["move"] == nil }))
        XCTAssertFalse(has("Am PC beenden und hier fortsetzen", 1.5))  // Knopf und Rückfrage sind entfernt
        XCTAssertTrue(has("Verwerfen", 3))  // die Nachricht wartet weiter im Postausgang
        XCTAssertFalse(mockReceived("send", where: { $0["move"] != nil }, timeout: 2))
    }

    func test15_RefusedMessageGoesOutLater() {
        // Abgelehnt, weil die Sitzung am PC ohne tmux läuft: die Nachricht wartet (Zeile im Chat und in der Sitzungsliste)
        // und geht von selbst hinaus, sobald die Sitzung in tmux läuft (am PC mit claude --resume neu geöffnet).
        launchConnected()
        openSession("Skript ohne tmux")
        typeInto("chatInput", "Bitte später senden")
        tapID("chatSend")
        settle(1.5)
        expect("Geht von selbst hinaus", 5)
        shot("abgelehnt-wartet")
        back()
        reveal("Skript ohne tmux")
        expect("1 Nachricht wartet auf die Sitzung", 5, soft: true)
        shot("liste-nachricht-wartet")
        ctl("trigger_desk_to_tmux")
        let end = Date().addingTimeInterval(40)
        var sends = 0
        repeat {
            sends = rpcLog().filter { ($0["method"] as? String) == "send" && (($0["params"] as? [String: Any])?["text"] as? String) == "Bitte später senden" }.count
            if sends >= 2 { break }
            settle(0.5)
        } while Date() < end
        XCTAssertGreaterThanOrEqual(sends, 2, "die abgelehnte Nachricht ging nicht von selbst noch einmal hinaus")
    }

    func test16_ReplyAfterReconnect() {
        // 11.11.2026: Der Agent antwortete, während die Verbindung getrennt war; der offene Chat zeigte die Antwort nicht.
        // Nach der neuen Verbindung lädt der Chat den Verlauf nach und meldet das Mitlesen neu an.
        launchConnected()
        openSession("API Refactoring")
        settle(1)
        ctl("offline"); ctl("kick")
        settle(3)
        ctl("trigger_late_reply")  // bleibt liegen, bis wieder eine Verbindung steht
        ctlRemove("offline")
        XCTAssertTrue(has("Antwort nach der Trennung", 40), "die Antwort erscheint nach dem Wiederverbinden nicht im offenen Chat")
        shot("antwort-nach-wiederverbinden")
        let watches = rpcLog().filter { ($0["method"] as? String) == "watch" }.count
        XCTAssertGreaterThanOrEqual(watches, 2, "das Mitlesen wurde nach der neuen Verbindung nicht neu angemeldet")
    }

    func test12_HideKeyboard() {
        // Tastatur offen: der Knopf sitzt rechts in der Schnellantwort-Zeile über dem Eingabefeld (seit 0.3.8), verdeckt
        // weder Senden noch Mikrofon und schließt die Tastatur; der getippte Text bleibt im Feld.
        launchConnected()
        openSession("API Refactoring")
        typeInto("chatInput", "Tastatur zu")
        settle(0.8)
        shot("tastatur-offen")
        XCTAssertTrue(id("hideKeyboard").waitForExistence(timeout: 4), "Knopf Tastatur ausblenden fehlt bei offener Tastatur")
        let hide = id("hideKeyboard").frame, send = id("chatSend").frame, mic = id("chatMic").frame, field = id("chatInput").frame
        XCTAssertFalse(hide.intersects(send), "Knopf überdeckt Senden: \(hide) / \(send)")
        XCTAssertFalse(hide.intersects(mic), "Knopf überdeckt Mikrofon: \(hide) / \(mic)")
        XCTAssertLessThanOrEqual(hide.maxY, field.minY + 1, "Knopf liegt nicht über dem Eingabefeld: \(hide) / \(field)")
        XCTAssertGreaterThanOrEqual(hide.height, 43, "Tippfläche zu klein: \(hide)")
        XCTAssertTrue(id("chatSend").isHittable, "Senden bei offener Tastatur nicht antippbar")
        XCTAssertTrue(id("chatMic").isHittable, "Mikrofon bei offener Tastatur nicht antippbar")
        tapID("hideKeyboard")
        settle(1)
        shot("tastatur-zu")
        XCTAssertEqual(app.keyboards.count, 0, "Tastatur noch offen")
        let value = id("chatInput").value as? String ?? ""
        XCTAssertTrue(value.contains("Tastatur zu"), "Text weg: \(value)")
    }

    func test14_ReadingMode() {
        // Lesemodus: Leisten und Eingabezeile weg, der Verlauf bleibt; der kleine Knopf oben rechts holt alles zurück.
        launchConnected()
        openSession("API Refactoring")
        tapID("readingOn")
        settle(1.2)
        shot("lesemodus-an")
        XCTAssertFalse(id("chatInput").exists, "Eingabezeile im Lesemodus sichtbar")
        if app.navigationBars.count > 0 { notes.append("Navigationsleiste im Lesemodus noch im Baum (\(app.navigationBars.count))") }
        expect("Zusammenfassung", 4, soft: true)
        tapID("readingOff")
        settle(1.2)
        shot("lesemodus-aus")
        XCTAssertTrue(id("chatInput").waitForExistence(timeout: 4), "Eingabezeile nach dem Lesemodus fehlt")
        XCTAssertTrue(id("readingOn").waitForExistence(timeout: 4), "Lesemodus-Knopf nach dem Lesemodus fehlt")
    }
}
