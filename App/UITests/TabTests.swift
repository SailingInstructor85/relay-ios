import XCTest

/// Die Tab-Navigation: Heute, Dein Zug, Posteingang, Mehr. Läuft in der CI im Teil „design“.
final class TabTests: RelayTestCase {
    /// Heute zeigt die Abschnitte, eine Sitzungskarte öffnet den Chat, Zurück führt wieder zu Heute.
    func test01_HeuteOeffnetSitzung() {
        launchConnected()
        showTab(Self.tabToday)
        settle(1.5)
        shot("heute")
        expect("Braucht dich", 5)
        XCTAssertTrue(id("assistantCard").waitForExistence(timeout: 4), "Assistent-Karte fehlt")
        XCTAssertTrue(revealInPage("API Refactoring"), "Sitzungskarte fehlt auf Heute")
        tap("API Refactoring", 5)
        XCTAssertTrue(id("chatInput").waitForExistence(timeout: 8), "Chat nicht geöffnet")
        shot("heute-chat")
        XCTAssertFalse(app.tabBars.buttons["Heute"].isHittable, "Tab-Leiste im Chat sichtbar")
        back()
        settle(0.8)
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 5), "Tab-Leiste nach dem Chat nicht zurück")
    }

    /// Die Eingabeleiste auf Heute stellt die Frage an Jarvis und öffnet dessen Ansicht.
    func test02_HeuteFragtJarvis() {
        launchConnected()
        showTab(Self.tabToday)
        settle(1)
        typeInto("todayInput", "Was läuft gerade?")
        shot("heute-eingabe")
        tapID("todaySend")
        settle(1.5)
        shot("heute-jarvis")
        XCTAssertTrue(mockReceived("ask", where: { ($0["text"] as? String) == "Was läuft gerade?" }), "ask mit der Frage fehlt")
        XCTAssertTrue(id("jarvisInput").waitForExistence(timeout: 5), "Jarvis nicht geöffnet")
    }

    /// Dein Zug: eine Rückfrage wird direkt auf der Karte mit „Ja (Empfehlung)“ beantwortet.
    func test03_DeinZugRueckfrage() {
        launchConnected()
        ctl("trigger_rueckfrage")
        settle(3)
        showTab(Self.tabYourTurn)
        settle(1)
        shot("deinzug-rueckfrage")
        expect("Soll ich die alte Route", 6)
        tapID("turnYes")
        XCTAssertTrue(mockReceived("inbox_put"), "Antwort nicht per inbox_put gesendet")
        settle(1.5)
        shot("deinzug-nach-antwort")
    }

    /// Dein Zug: eine Freigabe wird auf der Karte freigegeben.
    func test04_DeinZugFreigabe() {
        launchConnected()
        ctl("trigger_send_request")
        settle(3)
        showTab(Self.tabYourTurn)
        settle(1)
        shot("deinzug-freigabe")
        expect("E-Mail freigeben?", 6)
        tapID("turnApprove")
        XCTAssertTrue(mockReceived("send_result", where: { $0["ok"] as? Bool == true }), "Freigabe nicht gesendet")
    }

    /// Wartende Sitzung in Dein Zug öffnet den Chat; Posteingang (Liste aus dem Mock) und Mehr stehen.
    func test05_TabsUndPosteingang() {
        launchConnected()
        showTab(Self.tabYourTurn)
        settle(1)
        XCTAssertTrue(revealInPage("Chat öffnen"), "keine wartende Sitzung in Dein Zug")
        tapID("turnOpenChat")
        XCTAssertTrue(id("chatInput").waitForExistence(timeout: 8), "Chat aus Dein Zug nicht geöffnet")
        showTab(Self.tabInbox)
        expect("Unterlagen für Donnerstag", 10)
        shot("posteingang")
        showTab(Self.tabMore)
        expect("Einstellungen", 4)
        expect("Nutzung & Limits", 4)
        shot("mehr")
        showSessions()
        expect("Laufend", 4)
    }

    /// Wartet, bis ein Text nicht mehr zu sehen ist.
    private func gone(_ s: String, _ timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if find(s) == nil { return true }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < end
        return false
    }

    /// Dein Zug: „Erledigt“ schließt eine Rückfrage ohne Antwort (nach Nachfrage). Der PC bekommt „(verworfen)“.
    func test06_DeinZugRueckfrageErledigt() {
        launchConnected()
        ctl("trigger_rueckfrage")
        settle(3)
        showTab(Self.tabYourTurn)
        settle(1)
        expect("Soll ich die alte Route", 6)
        tapID("turnDismiss")
        settle(0.8)
        shot("deinzug-rueckfrage-erledigt")
        tap("Ohne Antwort schließen", 4, exact: true)
        XCTAssertTrue(mockReceived("inbox_put", where: { p in
            ((p["items"] as? [[String: Any]])?.first?["app"] as? String) == "rueckfrage" && ((p["items"] as? [[String: Any]])?.first?["text"] as? String) == "(verworfen)"
        }), "„(verworfen)“ nicht per inbox_put gesendet")
        XCTAssertTrue(gone("Soll ich die alte Route"), "verworfene Rückfrage steht noch in Dein Zug")
    }

    /// Eine am PC beantwortete Rückfrage (Ereignis rueckfrage_resolved) verschwindet aus Dein Zug und zeigt in den
    /// Hinweisen die Antwort vom PC.
    func test07_RueckfrageAmPCBeantwortet() {
        launchConnected()
        ctl("trigger_rueckfrage")
        settle(3)
        showTab(Self.tabYourTurn)
        settle(1)
        expect("Soll ich die alte Route", 6)
        ctl("trigger_rueckfrage_pc")
        XCTAssertTrue(gone("Soll ich die alte Route", 10), "am PC beantwortete Rückfrage steht noch in Dein Zug")
        shot("deinzug-am-pc-beantwortet")
        mainMenu("Hinweise")
        settle(1.5)
        tap("Rückfrage R1", soft: true)
        settle(1.5)
        expect("Beantwortet: nein, behalten", 4, soft: true)
        shot("rueckfrage-am-pc-beantwortet")
    }

    /// App in den Hintergrund und wieder nach vorn (wie „App öffnen“).
    private func reopenApp() {
        XCUIDevice.shared.press(.home)
        settle(2)
        app.activate()
        settle(1)
    }

    /// Beim Öffnen der App geht das Blatt „Rückfrage jetzt“ mit der ältesten offenen Rückfrage auf (voller Wortlaut,
    /// Kontext, Empfehlung). „Später“ schließt es, beim nächsten Öffnen bleibt es zu, die Karte in Dein Zug bleibt.
    func test08_RueckfrageBlattSpaeter() {
        launchConnected()
        ctl("trigger_rueckfrage")
        settle(3)
        XCTAssertFalse(id("promptLater").exists, "Blatt darf nicht mitten in der Nutzung aufgehen")
        reopenApp()
        XCTAssertTrue(id("promptLater").waitForExistence(timeout: 25), "Blatt mit der offenen Rückfrage fehlt nach dem Öffnen")
        expect("Soll ich die alte Route", 4)
        expect("seit 2024 nicht mehr genutzt", 3, soft: true)
        expect("1 offene Rückfrage", 3, soft: true)
        shot("rueckfrage-blatt")
        tapID("promptLater")
        settle(1.5)
        XCTAssertFalse(id("promptLater").exists, "Blatt nach „Später“ noch offen")
        reopenApp()
        settle(6)
        XCTAssertFalse(id("promptLater").exists, "Blatt kommt nach „Später“ ohne neue Rückfrage wieder")
        showTab(Self.tabYourTurn)
        expect("Soll ich die alte Route", 6)
    }

    /// Im Blatt nimmt „Ja (Empfehlung)“ die Empfehlung an: Antwort „ja“ geht zum PC, das Blatt schließt sich.
    func test09_RueckfrageBlattJa() {
        launchConnected()
        ctl("trigger_rueckfrage")
        settle(3)
        reopenApp()
        XCTAssertTrue(id("promptYes").waitForExistence(timeout: 25), "Blatt mit der offenen Rückfrage fehlt nach dem Öffnen")
        tapID("promptYes")
        XCTAssertTrue(mockReceived("inbox_put", where: { p in
            ((p["items"] as? [[String: Any]])?.first?["app"] as? String) == "rueckfrage" && ((p["items"] as? [[String: Any]])?.first?["text"] as? String) == "ja"
        }), "Antwort „ja“ nicht per inbox_put gesendet")
        settle(2)
        XCTAssertFalse(id("promptYes").exists, "Blatt nach der Antwort noch offen")
        shot("rueckfrage-blatt-beantwortet")
    }

    /// Smart Home im Tab „Mehr“: „HDMI 2 aktivieren“ schickt nur Gerät und Aktionsnamen ans Gateway, die Rückmeldung
    /// des Skripts steht danach oben auf der Seite.
    func test10_SmartHomeFernseher() {
        launchConnected()
        showTab(Self.tabMore)
        expect("Smart Home", 5)
        tap("Smart Home", 4)
        expect("Fernseher einschalten", 5)
        expect("Fernseher ausschalten", 3)
        shot("smarthome")
        tapID("smartHome.hdmi2")
        XCTAssertTrue(mockReceived("smart_home", where: { ($0["device"] as? String) == "tv" && ($0["action"] as? String) == "hdmi2" }),
                      "smart_home mit HDMI 2 nicht aufgerufen")
        expect("Umgeschaltet auf HDMI 2", 6)
        shot("smarthome-ergebnis")
    }
}
