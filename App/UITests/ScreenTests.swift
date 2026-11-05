import XCTest

final class ScreenTests: RelayTestCase {
    func test01_QuestionForm() {
        launchConnected()
        openSession("Abrechnung einrichten")
        settle(2)
        shot("frage-formular")
        expect("Welchen Tarif", 5)
        tap("Pro", soft: true)
        settle(0.5); shot("frage-pro-gewaehlt")
        tap("Weiter", 2, soft: true)
        settle(0.8); shot("frage-zweite")
        tap("Export als CSV", 2, soft: true)
        settle(0.5); shot("frage-mehrfach")
        tap("Antworten senden", 3, soft: true)
        settle(2); shot("frage-beantwortet")
        XCTAssertTrue(mockReceived("send", where: { $0["steps"] != nil || $0["keys"] != nil }), "Antwort kam nicht beim Mock an")
    }

    func test02_QuestionDecline() {
        launchConnected()
        openSession("Abrechnung einrichten")
        settle(2)
        tap("Ablehnen", soft: true)
        settle(1.5)
        shot("frage-abgelehnt")
    }

    func test03_ModelMenuCard() {
        launchConnected()
        openSession("Modell wechseln")
        settle(2.5)
        shot("menuekarte-modell")
        expect("Sonnet", 4, soft: true)
        tap("Sonnet", soft: true)
        settle(1.5)
        shot("menuekarte-gewaehlt")
        XCTAssertTrue(mockReceived("send", where: { $0["keys"] != nil || $0["steps"] != nil }))
    }

    func test04_PermissionPrompt() {
        launchConnected()
        openSession("Freigabe: Bash-Befehl")
        settle(2.5)
        shot("freigabe-prompt")
        expect("Do you want to proceed", 4, soft: true)
        tap("1. Yes", soft: true)
        settle(1.5)
        shot("freigabe-ja")
    }

    func test05_PanelCard() {
        launchConnected()
        openSession("Einstellungen offen")
        settle(2.5)
        shot("panel-karte")
        expect("Settings", 4, soft: true)
    }

    func test06_FormCard() {
        launchConnected()
        openSession("Formular im Terminal")
        settle(2.5)
        shot("formular-karte")
        expect("Which size", 4, soft: true)
    }

    func test07_LiveScreenAndKeyBar() {
        launchConnected()
        openSession("API Refactoring")
        tapID("chatMenu")
        tap("Live-Bildschirm")
        settle(2.5)
        shot("live-bildschirm")
        expect("pytest", 4, soft: true)
        for k in ["Esc", "↑", "↓", "Tab", "1"] {
            if let e = find(k, exact: true), e.exists, e.frame.maxX < 400, e.frame.minX >= 0 { e.tap(); settle(0.3) }
        }
        settle(0.8)
        shot("live-bildschirm-tasten")
        XCTAssertTrue(mockReceived("send", where: { ($0["keys"] as? [String])?.contains("Up") == true }))
        let f = app.textFields["Text tippen (ohne Enter)"]
        if f.exists { f.tap(); f.typeText("ls"); tap("Senden", exact: true, soft: true) }
        tap("Größer", 1, soft: true)
        shot("live-bildschirm-text")
        tap("Fertig", exact: true, soft: true)
    }
}
