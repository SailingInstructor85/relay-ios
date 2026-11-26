import XCTest

/// Tab „Posteingang“ (Liste, Mail lesen, Suche, Aufräumvorschläge, Zustände ohne Daten) und die Kalenderkarte auf
/// „Heute“ mit der Wochenliste. Die Daten kommen aus dem Mock-Gateway (erfunden). Alles ist nur lesend: Kein Test
/// darf einen RPC zum Senden, Antworten oder Löschen auslösen. Läuft in der CI im Teil „design“.
final class InboxTests: RelayTestCase {
    static let firstSubject = "Unterlagen für Donnerstag"
    /// RPCs, die die App im Posteingang nie aufrufen darf.
    static let writing = ["inbox_mail_reply", "inbox_mail_delete", "inbox_mail_delete_many", "inbox_mail_keep", "inbox_mail_send"]

    private func openInbox() {
        showTab(Self.tabInbox)
        settle(1)
    }

    private func assertNothingWritten(file: StaticString = #filePath, line: UInt = #line) {
        let used = Set(rpcLog().compactMap { $0["method"] as? String })
        for m in Self.writing { XCTAssertFalse(used.contains(m), "Schreibender RPC aufgerufen: \(m)", file: file, line: line) }
    }

    /// Die Liste zeigt Absender, Betreff und Tage; ein Tipp öffnet die Mail mit Text und Anhängen; Zurück führt zur Liste.
    func test01_ListeUndMail() {
        launchConnected()
        openInbox()
        expect(Self.firstSubject, 10)
        expect("Anna Muster", 4)
        expect("Stadtbibliothek Beispielstadt", 4)
        XCTAssertTrue(mockReceived("inbox_feed"), "inbox_feed nicht aufgerufen")
        XCTAssertTrue(id("inboxSearch").exists, "Suchfeld fehlt")
        shot("posteingang")
        tap(Self.firstSubject, 5)
        XCTAssertTrue(id("mailSubject").waitForExistence(timeout: 8), "Mailansicht nicht geöffnet")
        // Der Mailtext steht in einem markierbaren Textfeld (langes Drücken markiert Text), siehe `hasSelectableText`.
        XCTAssertTrue(hasSelectableText("anbei der Ablaufplan", 5) || has("anbei der Ablaufplan", 2), "Erwartet, aber nicht da: anbei der Ablaufplan")
        if !(hasSelectableText("https://example.org/ablaufplan", 3) || has("example.org/ablaufplan", 2)) { notes.append("Mail: Link nicht im Mailtext gefunden") }
        expect("Ablaufplan.pdf", 4)
        expect("anna.muster@example.org", 4)
        XCTAssertTrue(mockReceived("inbox_mail", where: { ($0["id"] as? String) == "1042" }), "inbox_mail mit der Nummer fehlt")
        shot("mail")
        XCTAssertTrue(app.tabBars.buttons[Self.tabInbox].exists, "Tab-Leiste fehlt in der Mailansicht")
        // Tipp auf den Link: Im Test öffnet die App nichts, sie zeigt nur, was sie geöffnet hätte. Weich geprüft,
        // weil der Link im Textfeld je nach iOS-Version anders im Baum steht.
        let link = app.links.matching(NSPredicate(format: "label CONTAINS[c] %@", "example.org/ablaufplan")).firstMatch
        if link.waitForExistence(timeout: 2) {
            link.tap()
            if id("mailLinkOpened").waitForExistence(timeout: 3) { shot("mail-link") } else { notes.append("Mail: Tipp auf den Link kam nicht an") }
        } else {
            notes.append("Mail: Link nicht als Element im Baum")
        }
        back()
        expect(Self.firstSubject, 5)
        assertNothingWritten()
    }

    /// Die Suche fragt das Gateway (alle Jahre), zeigt Treffer mit Vorschau und lässt sich wieder beenden.
    func test02_Suche() {
        launchConnected()
        openInbox()
        expect(Self.firstSubject, 10)
        typeInto("inboxSearch", "rechn", enter: true)
        XCTAssertTrue(mockReceived("inbox_search", where: { ($0["q"] as? String) == "rechn" }), "inbox_search mit dem Suchtext fehlt")
        expect("Rechnung 2024-118", 8)
        expect("Treffer für", 4)
        expect("die Rechnung ist überwiesen", 4)
        shot("suche")
        tapID("inboxSearchClear")
        expect(Self.firstSubject, 5)
        // zu kurzer Suchtext: Hinweis, kein Aufruf
        typeInto("inboxSearch", "a", enter: true)
        expect("Mindestens zwei Zeichen", 4)
        XCTAssertFalse(rpcLog().contains { ($0["method"] as? String) == "inbox_search" && (($0["params"] as? [String: Any])?["q"] as? String) == "a" },
                       "Suche mit einem Zeichen gesendet")
        assertNothingWritten()
    }

    /// Aufräumvorschläge klappen auf und zeigen Absender, Anzahl und Grund. Es gibt keine Aktion dazu.
    func test03_Aufraeumvorschlaege() {
        launchConnected()
        openInbox()
        XCTAssertTrue(mockReceived("inbox_mail_suggest"), "inbox_mail_suggest nicht aufgerufen")
        XCTAssertTrue(id("inboxSuggestions").waitForExistence(timeout: 10), "Zeile Aufräumvorschläge fehlt")
        expect("3 Absender, 29 Mails", 4)
        tapID("inboxSuggestions")
        expect("14 Mails · Newsletter", 5)
        expect("9 Mails · Werbung", 4)
        expect("Nur zur Ansicht", 4)
        shot("vorschlaege")
        XCTAssertNil(find("Behalten"), "Knopf Behalten darf es nicht geben")
        XCTAssertNil(find("Papierkorb"), "Löschen darf es nicht geben")
        tapID("inboxSuggestions")
        assertNothingWritten()
    }

    /// Ein Gateway ohne Posteingang und Kalender: klarer Fehlerzustand, keine Kalenderkarte; nach „Erneut laden“ steht die Liste.
    func test04_GatewayOhnePosteingang() {
        ctl("inbox_off")
        launchConnected()
        openInbox()
        expect("Gateway liefert keinen Posteingang", 10)
        XCTAssertTrue(id("inboxRetry").exists, "Knopf Erneut laden fehlt")
        shot("ohne-posteingang")
        showTab(Self.tabToday)
        settle(2)
        XCTAssertFalse(id("calendarCard").exists, "Kalenderkarte ohne Kalender im Gateway")
        expect("Braucht dich", 4)
        shot("heute-ohne-kalender")
        // Zurück im Posteingang steht der Fehler noch; erst mit dem Posteingang im Gateway lädt „Erneut laden“ die Liste.
        openInbox()
        expect("Gateway liefert keinen Posteingang", 6)
        ctlRemove("inbox_off")
        tapID("inboxRetry")
        expect(Self.firstSubject, 10)
    }

    /// Leerer Posteingang und leerer Kalender: ruhige Leerzustände statt Fehler.
    func test05_Leer() {
        ctl("inbox_empty")
        launchConnected()
        openInbox()
        expect("Nichts in den letzten 7 Tagen", 10)
        XCTAssertFalse(id("inboxSuggestions").exists, "Aufräumvorschläge ohne Vorschläge sichtbar")
        shot("leer")
        showTab(Self.tabToday)
        XCTAssertTrue(id("calendarCard").waitForExistence(timeout: 10), "Kalenderkarte fehlt bei leerem Kalender")
        expect("Keine Termine", 4)
    }

    /// Heute zeigt die Termine von heute und morgen; ein Tipp öffnet die Wochenliste, Zurück führt wieder zu Heute.
    func test06_KalenderkarteUndWoche() {
        launchConnected()
        showTab(Self.tabToday)
        XCTAssertTrue(id("calendarCard").waitForExistence(timeout: 10), "Kalenderkarte fehlt auf Heute")
        XCTAssertTrue(mockReceived("calendar", where: { ($0["days"] as? Int) == 8 }), "calendar mit acht Tagen fehlt")
        expect("Zahnarzt", 5)
        expect("Werkstatt, Reifenwechsel", 4)
        expect("Morgen", 4)
        XCTAssertTrue(revealInPage("Zahnarzt"), "Kalenderkarte nicht in den sichtbaren Bereich gebracht")
        shot("heute-kalender")
        tapID("calendarCard")
        XCTAssertTrue(id("calendarStrip").waitForExistence(timeout: 8), "Wochenliste nicht geöffnet")
        expect("Abendessen mit Ben", 5)
        expect("Praxis am Markt", 4)
        expect("Privat", 4)
        shot("kalender-woche")
        app.swipeUp()
        settle(0.6)
        shot("kalender-woche-unten")
        back()
        XCTAssertTrue(id("assistantCard").waitForExistence(timeout: 5), "nach der Wochenliste nicht zurück auf Heute")
    }

    /// Der Kalender ohne Verbindung: einmal geladen, App beendet, ohne Gateway neu gestartet. Karte und Wochenliste
    /// zeigen den gespeicherten Stand mit „Stand von …“.
    func test07_KalenderOhneVerbindung() {
        launchConnected()
        showTab(Self.tabToday)
        XCTAssertTrue(id("calendarCard").waitForExistence(timeout: 10), "Kalenderkarte fehlt auf Heute")
        expect("Zahnarzt", 5)
        ctl("offline")
        app.terminate()
        launch(keep: true)
        // Die App startet im Tab „Heute“, das Gateway nimmt keine Verbindung an.
        XCTAssertTrue(id("calendarCard").waitForExistence(timeout: 20), "Kalenderkarte fehlt ohne Verbindung")
        XCTAssertTrue(revealInPage("Zahnarzt"), "gespeicherte Termine fehlen auf der Karte")
        expect("Werkstatt, Reifenwechsel", 4)
        expect("Stand von", 5)
        shot("heute-kalender-ohne-verbindung")
        tapID("calendarCard")
        XCTAssertTrue(id("calendarStrip").waitForExistence(timeout: 8), "Wochenliste ohne Verbindung nicht geöffnet")
        XCTAssertTrue(id("calendarStale").waitForExistence(timeout: 5), "Hinweis „Stand von …“ fehlt in der Wochenliste")
        expect("Abendessen mit Ben", 5)
        shot("kalender-woche-ohne-verbindung")
        ctlRemove("offline")
    }
}
