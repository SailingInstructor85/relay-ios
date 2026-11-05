import XCTest

final class ComposeTests: RelayTestCase {
    func test01_SendMessage() {
        launchConnected()
        openSession("API Refactoring")
        typeInto("chatInput", "Bitte teste die Route /v2/items")
        shot("senden-eingabe")
        tapID("chatSend")
        settle(1)
        shot("senden-gesendet")
        XCTAssertTrue(mockReceived("send", where: { ($0["text"] as? String)?.contains("/v2/items") == true }), "Mock hat die Nachricht nicht erhalten")
        expect("Verstanden", 8)
        settle(1)
        shot("senden-antwort")
    }

    func test02_SlashChips() {
        launchConnected()
        openSession("API Refactoring")
        typeInto("chatInput", "/")
        settle(1)
        shot("slash-vorschlag")
        expect("/compact", 3, soft: true)
        tap("/compact", soft: true)
        settle(0.5)
        shot("slash-gewaehlt")
    }

    func test03_SendToBusySession() {
        launchConnected()
        openSession("Bench-Skript reparieren")
        typeInto("chatInput", "Stopp bitte")
        tapID("chatSend")
        settle(1.5)
        shot("busy-gesendet")
        // Der Zugriff ueber tmux-Ziel umgeht die Busy-Sperre (wie im echten Gateway); "Trotzdem senden" erscheint nur ohne tmux.
        XCTAssertTrue(mockReceived("send", where: { ($0["text"] as? String) == "Stopp bitte" }))
        if has("Trotzdem senden", 1) { tap("Trotzdem senden", soft: true); settle(1); shot("busy-erzwungen") }
    }

    func test04_OutboxWhenOffline() {
        launchConnected()
        openSession("API Refactoring")
        ctl("offline"); ctl("kick")
        settle(4)
        typeInto("chatInput", "Nachricht ohne Verbindung")
        tapID("chatSend")
        settle(2)
        shot("outbox-grau")
        expect("Nachricht ohne Verbindung", 3)
        ctlRemove("offline")
        settle(12)
        shot("outbox-nach-wiederverbinden")
        XCTAssertTrue(mockReceived("send", where: { ($0["text"] as? String)?.contains("ohne Verbindung") == true }, timeout: 25), "Outbox hat nicht nachgesendet")
    }

    func test05_Attach() {
        launchConnected()
        openSession("API Refactoring")
        let clip = id("attach")
        if clip.exists { clip.tap(); settle(0.8); shot("anhang-menue"); expect("Datei", 2, soft: true); expect("Foto oder Video", 2, soft: true); app.tap() }
        else { notes.append("Büroklammer nicht gefunden"); shot("anhang-fehlt") }
    }

    func test06_Dictation() {
        launchConnected()
        openSession("API Refactoring")
        shot("diktat-knopf")
    }

    func test07_ModelMenu() {
        launchConnected()
        openSession("API Refactoring")
        // Titel antippen öffnet das Modellmenü
        if let t = find("opus") { t.tap(); settle(1); shot("modellmenue"); expect("Modell", 2, soft: true); app.tap() }
        else { notes.append("Kontextkopf nicht tippbar"); shot("kopf-fehlt") }
    }

    func test08_ShareUploadFlow() {
        launchConnected()
        // Upload direkt über rpc nicht möglich ohne Dateiauswahl; der Dateiauswahl-Dialog wird geöffnet.
        openSession("API Refactoring")
        let clip = id("attach")
        if clip.exists { clip.tap(); tap("Datei", soft: true); settle(2); shot("dateiauswahl"); if app.buttons["Abbrechen"].exists { app.buttons["Abbrechen"].tap() } }
    }
}
