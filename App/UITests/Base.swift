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

    func launch(prefill: Bool = true) {
        app = XCUIApplication()
        app.launchArguments += ["-relayUITest", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["RELAY_UI_HOST"] = "127.0.0.1"
        app.launchEnvironment["RELAY_UI_PORT"] = env["RELAY_UI_PORT"] ?? "2222"
        app.launchEnvironment["RELAY_UI_USER"] = env["RELAY_UI_USER"] ?? NSUserName()
        app.launchEnvironment["RELAY_UI_SEED"] = Self.seedHex
        app.launchEnvironment["RELAY_UI_PREFILL"] = prefill ? "1" : "0"
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

    /// Startet und wartet, bis die Sitzungsliste mit Daten da ist.
    func launchConnected() {
        launch()
        XCTAssertTrue(has("Wartet auf dich", 30), "Sitzungsliste nicht geladen")
        settle(1)
    }

    // MARK: finden

    private let kinds: [XCUIElement.ElementType] = [.button, .cell, .staticText, .textField, .textView, .secureTextField, .switch, .menuItem, .segmentedControl, .other]

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

    func mainMenu(_ item: String) {
        tapID("mainMenu")
        tap(item, 4)
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

    func row(_ t: String) -> XCUIElement? { reveal(t); return find(t) }

    func openSession(_ title: String) {
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
