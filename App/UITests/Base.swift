import XCTest

/// Gemeinsame Hilfen: App starten, Elemente nach Text finden, Screenshots, Steuerdateien des Mock-Gateways.
class RelayTestCase: XCTestCase {
    static let mockDir = "/tmp/relaymock"
    // Testschlüssel (erfunden, nur für den CI-Lauf; die CI trägt den passenden öffentlichen Schlüssel ein).
    static let seedHex = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
    var app: XCUIApplication!
    var shotNo = 0
    var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
        let fm = FileManager.default
        try? fm.removeItem(atPath: Self.mockDir + "/state.json")
        for f in (try? fm.contentsOfDirectory(atPath: Self.mockDir + "/control")) ?? [] { try? fm.removeItem(atPath: Self.mockDir + "/control/" + f) }
        try? fm.removeItem(atPath: Self.mockDir + "/rpc.jsonl")
    }

    override func tearDown() {
        if !notes.isEmpty {
            let a = XCTAttachment(string: notes.joined(separator: "\n"))
            a.name = "notes"; a.lifetime = .keepAlways
            add(a)
        }
    }

    var env: [String: String] { ProcessInfo.processInfo.environment }

    /// `scheme`: "dark" oder "light" erzwingt das Farbschema der App (UITestMode.colorScheme), nil lässt das des Simulators.
    func launch(prefill: Bool = true, share: Bool = false, scheme: String? = nil) {
        app = XCUIApplication()
        app.launchArguments += ["-relayUITest", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["RELAY_UI_HOST"] = "127.0.0.1"
        app.launchEnvironment["RELAY_UI_PORT"] = env["RELAY_UI_PORT"] ?? "2222"
        app.launchEnvironment["RELAY_UI_USER"] = env["RELAY_UI_USER"] ?? NSUserName()
        app.launchEnvironment["RELAY_UI_SEED"] = Self.seedHex
        app.launchEnvironment["RELAY_UI_PREFILL"] = prefill ? "1" : "0"
        if share { app.launchEnvironment["RELAY_UI_SHARE"] = "1" }
        if let scheme { app.launchEnvironment["RELAY_UI_SCHEME"] = scheme }
        app.launch()
        dismissSystemAlerts()
    }

    /// Systemdialoge (Mitteilungen erlauben usw.) wegtippen.
    func dismissSystemAlerts() {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 1.0)
            let alert = sb.alerts.firstMatch
            guard alert.exists else { continue }
            for t in ["Erlauben", "Allow", "Zulassen", "OK"] where alert.buttons[t].exists { alert.buttons[t].tap(); break }
        }
    }

    /// Startet und wartet, bis der Startbildschirm mit Daten da ist.
    func launchConnected(scheme: String? = nil) {
        launch(scheme: scheme)
        XCTAssertTrue(waitHome(60), "Startbildschirm nicht geladen")
        settle(1)
        // Die App startet im Tab „Heute“. Die bestehenden Tests erwarten die Sitzungsliste vorn.
        showSessions()
    }

    // MARK: Wege durch die App
    //
    // Nur die Hilfen in diesem Abschnitt wissen, wie die Navigation aufgebaut ist: fünf Tabs (Heute, Dein Zug,
    // Sitzungen, Posteingang, Mehr), das frühere Hauptmenü liegt als Seite im Tab „Mehr“, drei Einträge, die nur die
    // Liste betreffen, zusätzlich im Menü `listMenu` der Sitzungsliste. Ändert sich die Navigation, werden nur diese
    // Hilfen angepasst: `waitHome`, `showTab`, `showSessions`, `openMainMenu`, `mainMenu`, `openSession`.

    /// Kennung, die der Startbildschirm setzt, sobald er verbunden ist und Sitzungen hat (HomeReadyMarker in der App).
    static let homeReadyID = "homeReady"
    /// Sichtbarer Text der Sitzungsliste, nur noch als Ersatz, falls die Kennung im Baum fehlt.
    static let legacyHomeText = "Wartet auf dich"

    /// Wartet, bis der Tab-Rahmen steht und Daten vom Gateway da sind.
    @discardableResult
    func waitHome(_ timeout: TimeInterval = 60) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        var round = 0
        repeat {
            if id(Self.homeReadyID).exists { return true }
            round += 1
            // Ersatz erst nach einigen Runden: Die Kennung kommt mit der Verbindung. Fehlt sie im Baum, zeigt der
            // Abschnitt „Wartet auf dich“ im Tab „Sitzungen“, dass Daten da sind.
            if round > 10 {
                let sessions = app.tabBars.buttons[Self.tabSessions]
                if sessions.exists, sessions.isHittable, !sessions.isSelected { sessions.tap(); Thread.sleep(forTimeInterval: 0.6) }
                if find(Self.legacyHomeText) != nil {
                    notes.append("Kennung \(Self.homeReadyID) fehlt, Start am Text „\(Self.legacyHomeText)“ erkannt")
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < end
        return false
    }

    static let tabToday = "Heute", tabYourTurn = "Dein Zug", tabSessions = "Sitzungen", tabInbox = "Posteingang", tabMore = "Mehr"

    /// Wählt einen Tab über die Leiste unten. In Chat, Jarvis und Sprachmodus ist die Leiste ausgeblendet, dann geht es
    /// erst zurück. Ein Tipp auf den schon gewählten Tab führt zu dessen Wurzel (AppRouter.select).
    func showTab(_ title: String) {
        for _ in 0..<5 {
            let b = app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            if b.exists {
                if b.isHittable { b.tap(); settle(0.6); return }
                // Leiste von der Tastatur verdeckt: nichts antippen, was den Bildschirm wechselt
                if app.keyboards.count > 0 {
                    if !b.isSelected { notes.append("Tab-Leiste verdeckt, Tab \(title) nicht gewählt") }
                    return
                }
            }
            back()
        }
        notes.append("Tab nicht erreichbar: \(title)")
        shot("tab-fehlt-" + title)
    }

    /// Bringt die Sitzungsliste nach vorn (Tab „Sitzungen“).
    func showSessions() { showTab(Self.tabSessions) }

    /// Öffnet das frühere Hauptmenü, ohne etwas zu wählen (für Bilder): die Seite im Tab „Mehr“.
    func openMainMenu() { showTab(Self.tabMore) }

    /// Verlässt das Hauptmenü wieder: zurück zur Sitzungsliste.
    func closeMainMenu() { showSessions() }

    // MARK: finden

    private let kinds: [XCUIElement.ElementType] = [.link, .button, .cell, .staticText, .textField, .textView, .secureTextField, .switch, .menuItem, .segmentedControl, .other]

    func find(_ s: String, exact: Bool = false) -> XCUIElement? {
        let pred = exact ? NSPredicate(format: "label == %@ OR identifier == %@ OR value == %@", s, s, s)
                         : NSPredicate(format: "label CONTAINS[c] %@ OR identifier == %@ OR placeholderValue CONTAINS[c] %@", s, s, s)
        for k in kinds {
            let e = app.descendants(matching: k).matching(pred).firstMatch
            if e.exists { return e }
        }
        return nil
    }

    func has(_ s: String, _ timeout: TimeInterval = 4, exact: Bool = false) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if find(s, exact: exact) != nil { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < end
        return false
    }

    /// Text in einem markierbaren Textfeld (UITextView, etwa die Antworten im Jarvis-Chat): Dort steht der Text im
    /// Wert des Elements, nicht in der Beschriftung, `has` findet ihn deshalb nicht.
    func hasSelectableText(_ s: String, _ timeout: TimeInterval = 4) -> Bool {
        let pred = NSPredicate(format: "value CONTAINS[c] %@", s)
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if app.textViews.matching(pred).firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < end
        return false
    }

    @discardableResult
    func tap(_ s: String, _ timeout: TimeInterval = 5, exact: Bool = false, soft: Bool = false) -> Bool {
        if has(s, timeout, exact: exact), let e = find(s, exact: exact) {
            if e.isHittable { e.tap() } else { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            Thread.sleep(forTimeInterval: 0.4)
            return true
        }
        let msg = "Nicht gefunden: \(s)"
        notes.append(msg)
        shot("fehlt-" + s.prefix(20))
        if !soft { XCTFail(msg) }
        return false
    }

    func expect(_ s: String, _ timeout: TimeInterval = 6, soft: Bool = false) {
        if !has(s, timeout) {
            let msg = "Erwartet, aber nicht da: \(s)"
            notes.append(msg)
            if !soft { XCTFail(msg) }
        }
    }

    func id(_ s: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: s).firstMatch }

    func tapID(_ s: String, _ timeout: TimeInterval = 5) {
        let e = id(s)
        if e.waitForExistence(timeout: timeout) { e.tap(); Thread.sleep(forTimeInterval: 0.4) }
        else { XCTFail("Kennung nicht gefunden: \(s)"); shot("fehlt-" + s) }
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Einträge, die nur die Sitzungsliste betreffen: Sie liegen im Menü `listMenu` der Liste (und zusätzlich in „Mehr“).
    static let listMenuItems = ["Hintergrundläufe", "Alle gelesen", "Neu verbinden"]

    /// Wählt einen Eintrag des früheren Hauptmenüs. Die meisten liegen als Zeile im Tab „Mehr“ (Jarvis fragen,
    /// Hinweise, Routinen, Einstellungen, die vier Übersichten, Alle Sitzungen beenden, Desktop ausschalten), die
    /// Einträge aus `listMenuItems` im Menü der Sitzungsliste, damit der Test danach wieder auf der Liste steht.
    func mainMenu(_ item: String) {
        if Self.listMenuItems.contains(where: { item.hasPrefix($0) }) {
            showSessions()
            tapID("listMenu")
            tap(item, 4)
            return
        }
        openMainMenu()
        if !revealInPage(item) { notes.append("Eintrag in „Mehr“ nicht sichtbar: \(item)") }
        tap(item, 4)
    }

    /// Scrollt eine Seite (kein List), bis ein Eintrag antippbar ist. Anders als `reveal` ohne Ziehen nach unten am
    /// Anfang, damit nichts neu geladen wird.
    @discardableResult
    func revealInPage(_ s: String) -> Bool {
        for _ in 0..<4 { if let e = find(s), e.isHittable { return true }; Thread.sleep(forTimeInterval: 0.3) }
        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            if let e = find(s), e.isHittable { return true }
        }
        for _ in 0..<5 {
            app.swipeDown(velocity: .slow)
            if let e = find(s), e.isHittable { return true }
        }
        return false
    }

    /// Scrollt die Liste, bis ein Eintrag sichtbar ist (List rendert nur, was auf dem Bildschirm ist).
    @discardableResult
    func reveal(_ s: String) -> Bool {
        for _ in 0..<3 { if let e = find(s), e.isHittable { return true }; Thread.sleep(forTimeInterval: 0.3) }
        for _ in 0..<8 {
            app.swipeUp()
            if let e = find(s), e.isHittable { return true }
        }
        for _ in 0..<10 {
            app.swipeDown()
            if let e = find(s), e.isHittable { return true }
        }
        return false
    }

    /// Im Chat nach oben scrollen, bis ein Element sichtbar ist.
    @discardableResult
    func revealChat(_ s: String, max: Int = 30) -> Bool {
        if let e = find(s), e.isHittable { return true }
        for _ in 0..<5 {
            app.swipeUp(velocity: .fast)
            if let e = find(s), e.isHittable { return true }
        }
        for i in 0..<max {
            app.swipeDown(velocity: .fast)
            if let e = find(s), e.isHittable { return true }
            if i % 5 == 4 { Thread.sleep(forTimeInterval: 0.6) }
        }
        return false
    }

    func row(_ t: String) -> XCUIElement? { reveal(t); return find(t) }

    /// Öffnet den Chat einer Sitzung über ihren Titel in der Sitzungsliste.
    func openSession(_ title: String) {
        showSessions()
        reveal(title)
        tap(title, 8)
        Thread.sleep(forTimeInterval: 1.5)
    }

    func typeInto(_ idOrPlaceholder: String, _ text: String, enter: Bool = false) {
        var e = id(idOrPlaceholder)
        if !e.exists, let f = find(idOrPlaceholder) { e = f }
        guard e.waitForExistence(timeout: 5) else { XCTFail("Feld fehlt: \(idOrPlaceholder)"); return }
        e.tap()
        e.typeText(text + (enter ? "\n" : ""))
    }

    func dismissKeyboard() {
        if app.keyboards.count > 0 {
            let done = app.keyboards.buttons["Fertig"]
            if done.exists { done.tap() } else { app.tap() }
        }
    }

    // MARK: Screenshots

    func shot(_ name: String) {
        shotNo += 1
        let safe = name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "%@-%02d-%@", String(describing: type(of: self)), shotNo, safe)
        a.lifetime = .keepAlways
        add(a)
    }

    func settle(_ s: Double = 1.0) { Thread.sleep(forTimeInterval: s) }

    // MARK: Mock

    func ctl(_ name: String) {
        FileManager.default.createFile(atPath: Self.mockDir + "/control/" + name, contents: Data())
    }

    func ctlRemove(_ name: String) { try? FileManager.default.removeItem(atPath: Self.mockDir + "/control/" + name) }

    /// Alle Zeilen aus rpc.jsonl des Mocks.
    func rpcLog() -> [[String: Any]] {
        guard let s = try? String(contentsOfFile: Self.mockDir + "/rpc.jsonl", encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    func mockReceived(_ method: String, where match: (([String: Any]) -> Bool)? = nil, timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if rpcLog().contains(where: { ($0["method"] as? String) == method && (match?($0["params"] as? [String: Any] ?? [:]) ?? true) }) { return true }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < end
        return false
    }
}
