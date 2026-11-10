import XCTest
@testable import RelayCore

final class ConnectHelpTests: XCTestCase {
    private let lan = "192.168.58.40"
    private let tail = "100.73.162.18"

    private func facts(_ message: String, stage: ConnectDiagnosis.Stage? = .connect, hostKeyChanged: Bool = false,
                       wasConnected: Bool = false, network: Bool = true, wifi: Bool = true, vpn: Bool = false,
                       hosts: [String]? = nil, tailnetUp: Bool = true, pcSleeping: Bool = false) -> ConnectDiagnosis.Facts {
        ConnectDiagnosis.Facts(message: message, stage: stage, hostKeyChanged: hostKeyChanged, wasConnected: wasConnected,
                               network: network, wifi: wifi, vpn: vpn, hosts: hosts ?? [lan, tail], tailnetUp: tailnetUp,
                               pcSleeping: pcSleeping)
    }

    func testWhatThePCSaidCountsFirst() {
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Host-Schlüssel hat sich geändert", hostKeyChanged: true, tailnetUp: false)), .hostKeyChanged)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Anmeldung abgelehnt: ist der Schlüssel auf dem Desktop eingetragen (notifyd setup key)?")), .authRejected)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("notifyd daemon is not running (systemctl --user start notifyd)", stage: .serve)), .gatewayDown)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("mock gateway offline", stage: .serve)), .gatewayDown)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Gateway hat die Verbindung beendet", stage: .serve, wasConnected: true)), .interrupted)
    }

    func testPhoneSide() {
        XCTAssertEqual(ConnectDiagnosis.problem(facts("egal", network: false)), .noNetwork)
        // Fehler aus Martins Nutzungsprotokoll: Tailscale aus, nur die Tailscale-Adresse führt zum PC
        let seen = "Connection errors: SingleConnectionFailure(target: [IPv4]100.73.162.18/100.73.162.18:22, error: connect(descriptor:addr:size:): Address already in use)"
        XCTAssertEqual(ConnectDiagnosis.problem(facts(seen, wifi: false, tailnetUp: false)), .tailscaleOff)
        XCTAssertEqual(ConnectDiagnosis.problem(facts(seen, tailnetUp: true)), .pcUnreachable)
        // nur die Adresse im Heimnetz eingetragen
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Zeitüberschreitung beim Verbinden", wifi: false, hosts: [lan], tailnetUp: false)), .noRoute)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Zeitüberschreitung beim Verbinden", wifi: true, hosts: [lan], tailnetUp: false)), .pcUnreachable)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Zeitüberschreitung beim Verbinden", wifi: false, vpn: true, hosts: [lan], tailnetUp: false)), .pcUnreachable)
    }

    func testPCSide() {
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Zeitüberschreitung beim Verbinden", pcSleeping: true)), .pcSleeping)
        // der PC hat den Ruhezustand angekündigt, dann reißt die Verbindung ab
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Gateway hat die Verbindung beendet", stage: .serve, wasConnected: true, pcSleeping: true)), .pcSleeping)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Zeitüberschreitung beim Verbinden")), .pcUnreachable)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Verbindung abgelehnt (läuft sshd?)")), .sshDown)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("nodename nor servname provided, or not known", hosts: ["arch.example.org"])), .badAddress)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("Already closed")), .interrupted)
        XCTAssertEqual(ConnectDiagnosis.problem(facts("etwas ganz anderes")), .unknown)
    }

    func testHelpTexts() {
        for p in ConnectProblem.allCases {
            let h = ConnectDiagnosis.help(p, message: "roh", hosts: [lan, tail], tailnetUp: true)
            XCTAssertEqual(h.problem, p)
            XCTAssertFalse(h.title.isEmpty, "\(p)")
            XCTAssertLessThanOrEqual(h.actions.count, 2, "\(p): höchstens zwei Knöpfe nebeneinander")
            XCTAssertEqual(h.isEmpty, p == .interrupted, "\(p)")
            XCTAssertFalse((h.title + h.text + h.steps.joined()).contains("–"), "\(p): kein Gedankenstrich")
        }
        let off = ConnectDiagnosis.help(.tailscaleOff, hosts: [tail])
        XCTAssertEqual(off.title, Tailnet.hint)
        XCTAssertEqual(off.actions, [.tailscaleConnect, .tailscaleOpen])
        let gw = ConnectDiagnosis.help(.gatewayDown, message: "notifyd daemon is not running (systemctl --user start notifyd)")
        XCTAssertTrue(gw.steps[0].contains(ConnectDiagnosis.gatewayStartCommand))
        XCTAssertEqual(gw.detail, "", "bekannte Meldung nicht doppelt zeigen")
        XCTAssertEqual(ConnectDiagnosis.help(.gatewayDown, message: "mock gateway offline").detail, "mock gateway offline")
        XCTAssertEqual(ConnectDiagnosis.help(.hostKeyChanged).actions.first, .acceptHostKey)
        XCTAssertEqual(ConnectDiagnosis.help(.authRejected).actions.first, .copySetupKey)
    }

    func testUnreachableMentionsTailscaleOnlyWhenUsed() {
        let viaTail = ConnectDiagnosis.help(.pcUnreachable, hosts: [tail], tailnetUp: true)
        XCTAssertTrue(viaTail.text.contains("Tailscale ist auf dem iPhone an"))
        XCTAssertEqual(viaTail.actions, [.tailscaleOpen])
        let lanOnly = ConnectDiagnosis.help(.pcUnreachable, hosts: [lan], tailnetUp: false)
        XCTAssertFalse(lanOnly.text.contains("Tailscale"))
        XCTAssertEqual(lanOnly.actions, [.relaySettings])
    }

    func testActionLabels() {
        for a in ConnectAction.allCases { XCTAssertFalse(a.label.isEmpty) }
        XCTAssertEqual(ConnectAction.tailscaleConnect.label, Tailnet.connectButton)
    }
}
