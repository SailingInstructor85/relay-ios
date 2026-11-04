import XCTest
@testable import RelayCore

final class TriageTests: XCTestCase {
    private func sess(_ key: String, state: String = "idle", act: Double = 0, asks: Bool = false, cwd: String = "/home/m/x") -> Session {
        Session.from(["key": .string(key), "state": .string(state), "last_activity": .number(act), "asks": .bool(asks), "cwd": .string(cwd)])!
    }

    func testQueueOrder() {
        let a = sess("claude:c1:a", state: "needs_input", act: 50)
        let b = sess("claude:c1:b", state: "needs_input", act: 10)
        let c = sess("claude:c1:c", act: 30)
        let d = sess("claude:c1:d", act: 90)
        let e = sess("claude:c1:e", act: 99)
        let unread: Set<String> = [c.key, d.key]
        let q = Triage.queue([a, b, c, d, e], unread: unread).map(\.key)
        XCTAssertEqual(q, [b.key, a.key, d.key, c.key])
        XCTAssertEqual(Triage.queue([a, b, c, d], unread: unread, current: b.key).map(\.key), [a.key, d.key, c.key])
        XCTAssertEqual(Triage.next([e], unread: []), nil)
        XCTAssertEqual(Triage.counts([a, b, c, d, e], unread: unread), Triage.Counts(need: 2, unread: 2))
        XCTAssertEqual(Triage.shortCount(Triage.Counts(need: 2, unread: 2)), "2 brauchen dich")
        XCTAssertEqual(Triage.shortCount(Triage.Counts(need: 0, unread: 3)), "3 ungelesen")
        XCTAssertEqual(Triage.shortCount(Triage.Counts(need: 0, unread: 0)), "")
    }

    func testAsksCountsAsWaiting() {
        let s = sess("claude:c1:a", state: "idle", asks: true)
        XCTAssertTrue(s.waits)
        XCTAssertEqual(Triage.counts([s], unread: [s.key]), Triage.Counts(need: 1, unread: 0))
    }

    func testRamCpuQuota() {
        let m = MemoryInfo(totalMb: 16000, availableMb: 5600, cpuPct: 63.4)
        XCTAssertEqual(Triage.ram(m)?.text, "10.2G")
        XCTAssertEqual(Triage.ram(m)?.level, 0)
        XCTAssertEqual(Triage.ram(MemoryInfo(totalMb: 1000, availableMb: 90))?.level, 2)
        XCTAssertEqual(Triage.ram(MemoryInfo(totalMb: 1000, availableMb: 190))?.level, 1)
        XCTAssertEqual(Triage.cpu(m)?.text, "CPU 63%")
        XCTAssertNil(Triage.cpu(MemoryInfo(totalMb: 1, availableMb: 1)))
        let u = JSON.object(["accounts": [
            ["alias": "c1", "tool": "claude", "windows": [["name": "5 h", "pct": 43.0], ["name": "week", "pct": 91.0]]],
            ["alias": "x1", "tool": "codex", "windows": []],
        ]])
        let qs = Triage.quota(u["accounts"].array.map(UsageAccount.from))
        XCTAssertEqual(qs.count, 1)
        XCTAssertEqual(qs[0].text, "43%"); XCTAssertEqual(qs[0].week, "91%"); XCTAssertEqual(qs[0].weekLevel, 2)
    }

    func testStale() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(Triage.staleText(lastSync: 10_000 - 300, now: now), "Stand vor 5 Min.")
        XCTAssertEqual(Triage.staleText(lastSync: 0, now: now), "")
    }

    func testClosedReason() {
        let s = Session.from(["key": "claude:c1:a", "closed": true, "closed_reason": "idle"])!
        XCTAssertEqual(s.closedReason, "idle")
    }
}

final class FuzzyTests: XCTestCase {
    func testMatching() {
        XCTAssertNotNil(Fuzzy.score("nta", "notify-app"))
        XCTAssertNil(Fuzzy.score("xyz", "notify-app"))
        XCTAssertNotNil(Fuzzy.score("", "abc"))
        XCTAssertNil(Fuzzy.score("app zz", "notify-app"))
        XCTAssertNotNil(Fuzzy.score("not app", "notify-app"))
    }

    func testSmartCase() {
        XCTAssertNil(Fuzzy.score("App", "notify-app"))
        XCTAssertNotNil(Fuzzy.score("App", "notify-App"))
        XCTAssertNotNil(Fuzzy.score("app", "notify-App"))
    }

    func testRanking() {
        let word = Fuzzy.score("app", "notify-app")!
        let scattered = Fuzzy.score("app", "axxpyyp")!
        XCTAssertGreaterThan(word, scattered)
        let lastPart = Fuzzy.score("app", "/zzz/app")!
        let early = Fuzzy.score("app", "/app/zzz")!
        XCTAssertGreaterThan(lastPart, early)
    }

    func testPositions() {
        XCTAssertEqual(Fuzzy.positions("app", "notify-app"), [7, 8, 9])
        XCTAssertEqual(Fuzzy.positions("zz", "notify-app"), [])
        XCTAssertEqual(Fuzzy.positions("no ap", "notify-app"), [0, 1, 7, 8])
    }
}

final class AvatarTests: XCTestCase {
    func testInitials() {
        XCTAssertEqual(Avatars.initials("/home/m/workspace/notify-app"), "NA")
        XCTAssertEqual(Avatars.initials("/home/m/audiobooks"), "Au")
        XCTAssertEqual(Avatars.initials("/home/m/helm_merge/"), "HM")
        XCTAssertEqual(Avatars.initials("/home/m"), "~")
    }

    func testAreaAndColor() {
        XCTAssertEqual(Avatars.areaOf("/home/m/workspace/musik/drei/src")?.area, "musik")
        XCTAssertEqual(Avatars.areaOf("/home/m/workspace/musik/drei/src")?.project, "drei")
        XCTAssertNil(Avatars.areaOf("/home/m/other"))
        XCTAssertEqual(Avatars.worktree("/home/m/workspace/a/b/.claude/worktrees/musik-drei"), "musik-drei")
        // same area, same colour; Kotlin "abc".hashCode() == 96354
        XCTAssertEqual(Avatars.javaHash("abc"), 96354)
        XCTAssertEqual(Avatars.color(cwd: "/h/workspace/a/x", look: Avatars.Look()), Avatars.color(cwd: "/h/workspace/a/y", look: Avatars.Look()))
    }

    func testLook() {
        let cfg = JSON.object([
            "avatars": ["musik": "🎵", "bad": "waytoolongvalue"],
            "avatar_colors": ["musik/drei": "#112233", "x": "red"],
            "avatar_topics": [["fix|bug", "🐛"]],
        ])
        let l = Avatars.look(from: cfg)
        XCTAssertEqual(l.map, ["musik": "🎵"])
        XCTAssertEqual(l.colors, ["musik/drei": 0x112233])
        XCTAssertEqual(Avatars.glyph(cwd: "/h/workspace/musik/drei", title: "Fix login", look: l), "🐛")
        XCTAssertEqual(Avatars.glyph(cwd: "/h/workspace/musik/drei", title: "x", look: l), "🎵")
        XCTAssertNil(Avatars.glyph(cwd: "/h/other", title: "x", look: l))
        XCTAssertEqual(Avatars.color(cwd: "/h/workspace/musik/drei", look: l), 0x112233)
    }
}

final class CloudTests: XCTestCase {
    func testCloudSession() {
        let list = JSON.object(["sessions": [["id": "c1", "state": "waiting", "title": "T", "question": "Q?"], ["state": "x"]]])
        let cs = list["sessions"].array.compactMap(CloudSession.from)
        XCTAssertEqual(cs.count, 1)
        XCTAssertTrue(cs[0].waiting)
        XCTAssertEqual(cs[0].question, "Q?")
    }
}
