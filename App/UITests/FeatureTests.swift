import XCTest

final class NewSessionTests: RelayTestCase {
    func test01_NewSessionFlow() {
        launchConnected()
        tapID("newSession")
        settle(1.5)
        shot("neu-start")
        expect("Neue Sitzung")
        expect("Konto", 3, soft: true)
        // Konto wählen
        tap("Konto", 2, soft: true)
        settle(0.8); shot("neu-konto-menue")
        tap("Codex", 2, soft: true)
        settle(0.5)
        // Ordnersuche
        let q = app.textFields["Ordner suchen…"]
        if q.exists { q.tap(); q.typeText("bill"); settle(2); shot("neu-ordnersuche"); }
        expect("/home/dev/workspace/billing", 4, soft: true)
        tap("/home/dev/workspace/billing", exact: true, soft: true)
        settle(0.8)
        shot("neu-ordner-gewaehlt")
    }

    func test02_BrowseAndMkdir() {
        launchConnected()
        tapID("newSession")
        settle(1.5)
        tap("Durchsuchen", soft: true)
        settle(2)
        app.swipeUp(); settle(0.5)
        shot("neu-durchsuchen")
        tap("workspace", 3, exact: true, soft: true)
        settle(1.5)
        app.swipeUp(); settle(0.5)
        shot("neu-workspace")
        let name = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Name'")).firstMatch
        if name.exists { name.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap(); name.typeText("neuprojekt"); dismissKeyboard() }
        for _ in 0..<4 where !has("Neuer Ordner", 0.5) { app.swipeDown() }
        tap("Neuer Ordner", soft: true)
        settle(1.5)
        shot("neu-mkdir")
        XCTAssertTrue(mockReceived("mkdir"), "mkdir nicht aufgerufen")
    }

    func test03_Launch() {
        launchConnected()
        tapID("newSession")
        settle(1.5)
        let q = app.textFields["Ordner suchen…"]
        q.tap(); q.typeText("webapp"); settle(2)
        shot("start-suche")
        tap("/home/dev/workspace/webapp", exact: true, soft: true)
        settle(0.6)
        let msg = app.textFields["Erste Nachricht"]
        if msg.exists { msg.tap(); msg.typeText("Hallo neue Sitzung"); dismissKeyboard() }
        shot("start-bereit")
        tap("Starten", 2, exact: true, soft: true)
        settle(4)
        shot("start-nach-launch")
        XCTAssertTrue(mockReceived("launch"), "launch nicht aufgerufen")
    }
}

final class InfoTests: RelayTestCase {
    func test01_Usage() {
        launchConnected()
        mainMenu("Nutzung & Limits")
        settle(2.5)
        shot("nutzung")
        expect("Codex", 4)
        expect("Reicht bis zum Reset", 3, soft: true)
        expect("leer um", 3, soft: true)
        expect("Pool-Helfer", 3, soft: true)
        app.swipeUp(); settle(0.5)
        shot("nutzung-unten")
        expect("Weitere Angaben", 3, soft: true)
        expect("Cloud-Guthaben", 3, soft: true)
        if tap("Details", 2, soft: true) { settle(1.5); shot("nutzung-details") }
    }

    func test02_UsageFromTriage() {
        launchConnected()
        settle(4)
        if let c = find("x1 ") { c.tap(); settle(2); shot("nutzung-aus-triage") } else { notes.append("Konto-Pille fehlt"); shot("triage-ohne-pille") }
    }

    func test03_Memory() {
        launchConnected()
        mainMenu("RAM-Monitor")
        settle(2.5)
        shot("ram")
        expect("Sitzungen", 3, soft: true)
        app.swipeUp(); settle(0.5)
        shot("ram-unten")
        expect("Geschlossen", 3, soft: true)
        expect("firefox", 3, soft: true)
    }

    func test04_Digest() {
        launchConnected()
        mainMenu("Was war los")
        settle(2.5)
        shot("digest")
        expect("API Refactoring", 3, soft: true)
        tap("30 Min.", 1, soft: true)
        settle(1); shot("digest-30min")
    }

    func test05_Tokens() {
        launchConnected()
        mainMenu("Token-Verbrauch")
        settle(2.5)
        shot("tokens")
        expect("API Refactoring", 3, soft: true)
        app.swipeUp(); settle(0.5); shot("tokens-unten")
    }

    func test06_Power() {
        launchConnected()
        mainMenu("Desktop ausschalten")
        settle(2.5)
        shot("power-vorschau")
        expect("Testlauf", 3, soft: true)
        expect("Bench-Skript", 3, soft: true)
        tap("Ausschalten", 2, soft: true)
        settle(1); shot("power-bestaetigung-1")
        app.swipeUp()
        shot("power-bestaetigung-1-unten")
    }

    func test07_Cloud() {
        launchConnected()
        settle(2)
        expect("Release vorbereiten", 5, soft: true)
        shot("cloud-in-liste")
    }

    func test08_Notices() {
        launchConnected()
        ctl("trigger_notice")
        settle(3)
        shot("hinweis-banner")
        mainMenu("Hinweise")
        settle(1.5)
        shot("hinweise-liste")
        expect("Backup braucht neuen Login", 4, soft: true)
        tap("Backup braucht neuen Login", soft: true)
        settle(1.5)
        shot("hinweis-detail")
        expect("example.com", 3, soft: true)
    }

    func test09_ApprovalStrip() {
        launchConnected()
        ctl("trigger_send_request")
        settle(3)
        shot("freigabe-streifen")
        if tap("E-Mail an frau@example.com", 3, soft: true) || tap("Freigabe", 2, soft: true) {
            settle(1.5); shot("freigabe-sheet")
            tap("Freigeben", 2, exact: true, soft: true)
            settle(1.5); shot("freigabe-erledigt")
            XCTAssertTrue(mockReceived("send_result", where: { $0["ok"] as? Bool == true }))
        }
    }

    func test10_Jarvis() {
        launchConnected()
        mainMenu("Jarvis fragen")
        settle(1.5)
        shot("jarvis-leer")
        typeInto("jarvisInput", "Was läuft gerade?")
        tapID("jarvisSend")
        settle(0.8)
        shot("jarvis-streamt")
        settle(5)
        shot("jarvis-antwort")
        expect("Du hast gefragt", 4)
        XCTAssertTrue(mockReceived("ask"))
    }

    func test11_JarvisMenuAndVocab() {
        launchConnected()
        mainMenu("Jarvis fragen")
        settle(1)
        let menus = app.navigationBars.buttons
        if menus.count > 1 { menus.element(boundBy: menus.count - 1).tap(); settle(0.8); shot("jarvis-menue") }
        tap("Erkennung korrigieren", 2, soft: true)
        settle(1.5)
        shot("jarvis-vokabular")
    }

    func test12_Settings() {
        launchConnected()
        mainMenu("Einstellungen")
        settle(1.5)
        shot("einstellungen-oben")
        for i in 1...6 {
            app.swipeUp(); settle(0.5)
            shot("einstellungen-scroll-\(i)")
        }
    }

    func test13_NotificationSettingsAndQuietHours() {
        launchConnected()
        mainMenu("Einstellungen")
        for _ in 0..<2 { app.swipeUp() }
        if let t = find("Ruhezeiten") {
            _ = t
        }
        shot("mitteilungen-abschnitt")
        let sw = app.switches["Ruhezeiten"]
        if sw.exists { sw.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); settle(0.8); shot("ruhezeiten-an"); expect("Von", 2, soft: true) }
        let sw2 = app.switches["Still, wenn ich am PC bin"]
        if sw2.exists { sw2.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); settle(0.5); shot("still-am-pc") }
    }

    func test14_VoiceSettings() {
        launchConnected()
        mainMenu("Einstellungen")
        for _ in 0..<5 {
            if has("Sprache und Stimme", 0.5) { break }
            app.swipeUp()
        }
        shot("sprache-stimme")
        expect("Erkennungssprache", 2, soft: true)
        tap("Testen", 1, soft: true)
        settle(1); shot("sprache-testen")
    }

    func test15_ProfileEditor() {
        launchConnected()
        mainMenu("Einstellungen")
        for _ in 0..<8 { if has("Persönliche Angaben", 0.4) { break }; app.swipeUp() }
        tap("Persönliche Angaben", soft: true)
        settle(2)
        shot("profil")
        expect("Erika", 3, soft: true)
        let f = app.textFields.matching(NSPredicate(format: "value CONTAINS 'Musterstadt'")).firstMatch
        if f.exists { f.tap(); f.typeText("x"); dismissKeyboard() }
        shot("profil-geaendert")
        tap("Auf dem Desktop speichern", 2, soft: true)
        settle(1.5); shot("profil-gespeichert")
    }

    func test16_JarvisAgentSettings() {
        launchConnected()
        mainMenu("Einstellungen")
        for _ in 0..<10 { if has("Jarvis-Agent", 0.4) { break }; app.swipeUp() }
        shot("jarvis-agent")
        XCTAssertTrue(mockReceived("get_config"))
    }

    func test17_ChatSettings() {
        launchConnected()
        mainMenu("Einstellungen")
        for _ in 0..<10 { if has("Return sendet", 0.4) { break }; app.swipeUp() }
        shot("sitzungs-einstellungen")
        let sw = app.switches["Return sendet"]
        if sw.exists { sw.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); settle(0.5); shot("return-sendet-an") }
    }

    func test18_HostKeyForget() {
        launchConnected()
        mainMenu("Einstellungen")
        settle(1)
        shot("hostkey-vor")
        for _ in 0..<3 where !has("Host-Schlüssel vergessen", 0.5) { app.swipeUp() }
        tap("Host-Schlüssel vergessen", soft: true)
        settle(5)
        shot("hostkey-neu-gepinnt")
    }

    func test19_LocationRequest() {
        launchConnected()
        ctl("trigger_location")
        settle(3)
        shot("standortanfrage")
    }
}
