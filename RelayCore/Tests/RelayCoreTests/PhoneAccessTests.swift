import XCTest
@testable import RelayCore

final class PhoneAccessTests: XCTestCase {
    private func cmd(_ name: String, _ args: [String: JSON] = [:], by: String = "agent", expires: Double = 0) -> PhoneCommand {
        PhoneCommand(id: "r1", name: name, args: args, requestedBy: by, reason: "Test", expiresAt: expires)
    }

    func testCommandFromEvent() {
        let ev: JSON = ["type": "phone_command", "request_id": "abc", "command": "files_list",
                        "args": ["folder": "scans"], "requested_by": "Jarvis", "reason": "Scan suchen", "expires_at": 100]
        let c = PhoneCommand.from(ev)
        XCTAssertEqual(c?.name, "files_list")
        XCTAssertEqual(c?.string("folder"), "scans")
        XCTAssertEqual(c?.requestedBy, "Jarvis")
        XCTAssertNil(PhoneCommand.from(["command": "device_info"]))
    }

    func testCatalogValidation() {
        XCTAssertNil(PhoneCatalog.validate(cmd("device_info")))
        XCTAssertNil(PhoneCatalog.validate(cmd("files_get", ["folder": "a", "path": "b.pdf"])))
        XCTAssertEqual(PhoneCatalog.validate(cmd("files_get", ["folder": "a"])), .unsupported)
        XCTAssertEqual(PhoneCatalog.validate(cmd("device_info", ["x": 1])), .unsupported)
        XCTAssertEqual(PhoneCatalog.validate(cmd("contacts_find")), .unsupported)
        XCTAssertEqual(PhoneCatalog.photoCount(cmd("photos_recent", ["count": 99])), 20)
        XCTAssertEqual(PhoneCatalog.photoCount(cmd("photos_recent")), 10)
        XCTAssertEqual(PhoneCatalog.maxPx(cmd("photos_get", ["id": "x", "max_px": 10])), 256)
        XCTAssertEqual(PhoneCatalog.maxPx(cmd("photos_get", ["id": "x"])), 2048)
    }

    func testPolicyOrder() {
        var s = PhoneSettings(areas: [.device, .files], folders: ["scans"])
        let now = 1000.0
        XCTAssertEqual(PhonePolicy.decide(cmd("device_info"), settings: s, foreground: false, now: now, log: []), .run)
        XCTAssertEqual(PhonePolicy.decide(cmd("device_info", expires: 999), settings: s, foreground: true, now: now, log: []), .refuse(.expired))
        XCTAssertEqual(PhonePolicy.decide(cmd("photos_recent"), settings: s, foreground: true, now: now, log: []), .refuse(.notAllowed))
        XCTAssertEqual(PhonePolicy.decide(cmd("files_list", ["folder": "drive"]), settings: s, foreground: true, now: now, log: []), .refuse(.notAllowed))
        XCTAssertEqual(PhonePolicy.decide(cmd("files_get", ["folder": "scans", "path": "../x"]), settings: s, foreground: true, now: now, log: []), .refuse(.notAllowed))
        XCTAssertEqual(PhonePolicy.decide(cmd("files_get", ["folder": "scans", "path": "2026/a.pdf"]), settings: s, foreground: true, now: now, log: []), .run)
        XCTAssertEqual(PhonePolicy.decide(cmd("nuke"), settings: s, foreground: true, now: now, log: []), .refuse(.unsupported))
        s.areas.insert(.clipboard)
        XCTAssertEqual(PhonePolicy.decide(cmd("clipboard_get"), settings: s, foreground: false, now: now, log: []), .waitForForeground)
        XCTAssertEqual(PhonePolicy.decide(cmd("clipboard_get"), settings: s, foreground: true, now: now, log: []), .run)
        s.killswitch = true
        XCTAssertEqual(PhonePolicy.decide(cmd("device_info"), settings: s, foreground: true, now: now, log: []), .refuse(.killswitch))
    }

    func testRateLimit() {
        let s = PhoneSettings(areas: [.device])
        let now = 10_000.0
        let log = (0..<30).map { PhoneLogEntry(id: "e\($0)", ts: now - 60, command: "device_info", requestedBy: "a", reason: "", outcome: "done") }
        XCTAssertEqual(PhonePolicy.decide(cmd("device_info", by: "a"), settings: s, foreground: true, now: now, log: log), .refuse(.rateLimit))
        XCTAssertEqual(PhonePolicy.decide(cmd("device_info", by: "b"), settings: s, foreground: true, now: now, log: log), .run)
        XCTAssertEqual(PhonePolicy.decide(cmd("device_info", by: "a"), settings: s, foreground: true, now: now + 3600, log: log), .run)
    }

    func testPaths() {
        XCTAssertEqual(PhonePaths.components(""), [])
        XCTAssertEqual(PhonePaths.components("2026/./scan.pdf"), ["2026", "scan.pdf"])
        XCTAssertNil(PhonePaths.components("/etc"))
        XCTAssertNil(PhonePaths.components("a/../../b"))
        XCTAssertNil(PhonePaths.components("~/x"))
    }

    func testFolderNames() {
        XCTAssertEqual(FolderNames.make("Bewerbungen", existing: []), "bewerbungen")
        XCTAssertEqual(FolderNames.make("Größe & Maße", existing: []), "groesse-masse")
        XCTAssertEqual(FolderNames.make("Scans", existing: ["scans"]), "scans-2")
        XCTAssertEqual(FolderNames.make("!!!", existing: []), "ordner")
    }

    func testCapsAndLog() {
        let s = PhoneSettings(killswitch: false, areas: [.photos, .device], folders: ["scans"])
        XCTAssertEqual(s.caps["areas"], ["device", "photos"])
        XCTAssertEqual(s.caps["folders"], ["scans"])
        XCTAssertEqual(s.caps.flag("killswitch"), false)
        let now = 100 * 86400.0
        let old = PhoneLogEntry(id: "old", ts: now - 31 * 86400, command: "device_info", requestedBy: "a", reason: "", outcome: "done")
        let mid = PhoneLogEntry(id: "mid", ts: now - 86400, command: "device_info", requestedBy: "a", reason: "", outcome: "done")
        let new = PhoneLogEntry(id: "new", ts: now, command: "photos_recent", requestedBy: "a", reason: "", outcome: "not_allowed")
        let list = PhoneLog.add(new, to: [mid, old], now: now)
        XCTAssertEqual(list.map(\.id), ["new", "mid"])
        XCTAssertEqual(PhoneLog.add(new, to: list, now: now).count, 2)
        XCTAssertEqual(PhoneLog.outcomeText("not_allowed"), "abgelehnt: Bereich oder Ordner nicht freigegeben")
        XCTAssertEqual(PhoneLog.size(1_258_291), "1,2 MB")
    }

    func testDeviceInfo() {
        let j = DeviceInfo.json(battery: 0.834, charging: true, freeBytes: 12_345_000_000, totalBytes: nil, ios: "18.1",
                                model: "iPhone17,1", app: "0.4.0", network: "WLAN")
        XCTAssertEqual(j.num("battery_percent"), 83)
        XCTAssertEqual(j.num("free_gb"), 12.3)
        XCTAssertEqual(j.flag("charging"), true)
        XCTAssertFalse(j.has("total_gb"))
        XCTAssertFalse(DeviceInfo.json(battery: -1, charging: nil, freeBytes: nil, totalBytes: nil, ios: "", model: "", app: "", network: "").has("battery_percent"))
    }
}
