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
        if clip.exists { clip.tap(); settle(0.8); shot("anhang-menue"); expect("Datei", 2, soft: true); expect("Fotos oder Videos", 2, soft: true)
            // The photo item must open the system picker (it did not while it was a PhotosPicker inside the Menu). Since 0.3.13
            // several can be picked; they wait as a preview (stagedMedia) until "N Fotos hochladen".
            let photoItem = app.buttons["Fotos oder Videos"]
            if photoItem.exists { photoItem.tap(); settle(2.5); shot("anhang-fotoauswahl")
                if app.buttons["attach"].isHittable { notes.append("Fotoauswahl hat sich nicht geöffnet") } }
            else { app.tap() } }
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

    func test09_VaultChatOffline() {
        // Ohne Verbindung: Chat für den Vault-Agenten öffnen, Nachricht wartet sichtbar und startet nach dem
        // Wiederverbinden genau einen Agenten im Vault mit der Nachricht als erster Eingabe.
        launchConnected()
        ctl("offline"); ctl("kick")
        settle(4)
        shot("vault-zeile-offline")
        tapID("vaultChat", 10)
        expect("Keine Verbindung zum PC", 5, soft: true)
        typeInto("vaultInput", "Notiz ohne Verbindung")
        tapID("vaultSend")
        settle(1)
        expect("wartet auf Verbindung", 5)
        shot("vault-wartet")
        ctlRemove("offline")
        XCTAssertTrue(mockReceived("launch", where: { p in
            (p["prompt"] as? String)?.contains("Notiz ohne Verbindung") == true && (p["name"] as? String)?.hasPrefix("Vom iPhone") == true
        }, timeout: 50), "Vault-Agent nicht gestartet")
        settle(2)
        shot("vault-zugestellt")
        let launches = rpcLog().filter { ($0["method"] as? String) == "launch" && (($0["params"] as? [String: Any])?["prompt"] as? String)?.contains("Notiz ohne Verbindung") == true }
        XCTAssertEqual(launches.count, 1, "Vault-Agent mehrfach gestartet")
    }

    func test10_ShareOpensNewSession() {
        // Geteilte Datei mit Nachricht: ohne Antippen eines Ziels startet eine neue Sitzung im Vault-Ordner,
        // keine bestehende Sitzung bekommt die Datei.
        launch(share: true)
        XCTAssertTrue(id("shareNew").waitForExistence(timeout: 60), "Teilen-Blatt nicht geöffnet")
        shot("teilen-blatt")
        if (id("shareNew").value as? String) != "gewählt" { notes.append("Haken an „Neue Sitzung“ nicht lesbar") }
        typeInto("shareMessage", "Bitte einsortieren")
        if id("shareSend").waitForExistence(timeout: 5) { id("shareSend").tap() } else { app.buttons["Starten"].firstMatch.tap() }
        XCTAssertTrue(mockReceived("launch", where: { p in
            let prompt = p["prompt"] as? String ?? ""
            return prompt.hasPrefix("Bitte einsortieren") && prompt.contains("testbrief.txt") && (p["name"] as? String) == "testbrief.txt"
        }, timeout: 40), "Neue Sitzung nicht gestartet")
        XCTAssertFalse(rpcLog().contains { ($0["method"] as? String) == "send" }, "Datei ging in eine bestehende Sitzung")
        settle(2)
        shot("teilen-neue-sitzung")
    }

    func test11_ShareToDocuments() {
        // „In Dokumente ablegen“: ein Agent mit eigenem Auftrag (erst fragen, dann verschieben) startet.
        launch(share: true)
        XCTAssertTrue(id("shareDocs").waitForExistence(timeout: 60), "Ziel „In Dokumente ablegen“ fehlt")
        tapID("shareDocs")
        shot("teilen-dokumente")
        if id("shareSend").waitForExistence(timeout: 5) { id("shareSend").tap() } else { app.buttons["Ablegen"].firstMatch.tap() }
        XCTAssertTrue(mockReceived("launch", where: { p in
            let prompt = p["prompt"] as? String ?? ""
            return prompt.contains("testbrief.txt") && prompt.contains("~/Dokumente/privat/Dokumente")
                && (p["name"] as? String) == "Dokument: testbrief.txt"
        }, timeout: 40), "Dokumenten-Agent nicht gestartet")
        settle(2)
        shot("teilen-dokumente-gestartet")
    }
}
