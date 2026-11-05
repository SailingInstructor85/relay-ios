import Foundation
import CoreLocation
import RelayCore

/// "Standort auf Anfrage": the Desktop asks once (`location_request`), the user taps the notification, Relay takes one
/// fix (app in the foreground, at most 60 s) and hands it to the Desktop. Never continuous, never in the background.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation, Error>?
    private var done: [String] = []

    override private init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// The event: only a notification; nothing is read before the user taps.
    func onRequest(_ ev: JSON, replay: Bool) {
        let id = ev.str("request_id")
        guard !id.isEmpty, !done.contains(id), ev.num("expires_at") > Date().timeIntervalSince1970 else { return }
        let reason = ev.str("reason")
        Notifier.post(id: "loc-\(id)", title: "Standort angefordert", body: reason.isEmpty ? "Der Desktop möchte deinen Standort. Tippen zum Senden." : "\(reason)\nTippen zum Senden.",
                      userInfo: ["locreq": id, "locexp": String(ev.num("expires_at"))])
    }

    /// The user tapped the notification.
    func fulfil(id: String, expires: Double) async {
        guard !done.contains(id) else { return }
        done.append(id)
        let model = AppModel.shared
        Notifier.remove(["loc-\(id)"])
        func fail(_ msg: String) async {
            if await model.connectOnce() {
                _ = try? await model.rpc("location_result", ["request_id": .string(id), "ok": false, "error": .string(msg)])
            }
            model.releaseBackground()
            model.lastError = "Standort nicht gesendet: \(msg)"
        }
        guard expires > Date().timeIntervalSince1970 else { model.lastError = "Die Standortanfrage ist abgelaufen."; return }
        // the fix needs the foreground (permission "beim Verwenden")
        for _ in 0..<20 where !model.isForeground { try? await Task.sleep(nanoseconds: 500_000_000) }
        guard model.isForeground else { return await fail("Relay war nicht geöffnet") }
        let loc: CLLocation
        do { loc = try await fix() } catch { return await fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) }
        guard await model.connectOnce() else { model.lastError = "Standort nicht gesendet: keine Verbindung"; return }
        let ts = loc.timestamp.timeIntervalSince1970
        let item: JSON = .object(["id": .string("loc-\(id)"), "ts": .number(ts), "lat": .number(loc.coordinate.latitude),
                                  "lon": .number(loc.coordinate.longitude), "accuracy_m": .number(loc.horizontalAccuracy),
                                  "provider": "ios", "request_id": .string(id)])
        do {
            _ = try await model.rpc("inbox_put", ["kind": "location", "items": [item]], timeout: 30)
            _ = try await model.rpc("location_result", ["request_id": .string(id), "ok": true, "lat": .number(loc.coordinate.latitude),
                                                         "lon": .number(loc.coordinate.longitude), "accuracy_m": .number(loc.horizontalAccuracy), "ts": .number(ts)])
            Approvals.shared.show("Standort gesendet.")
        } catch { model.lastError = "Standort nicht gesendet: \(error.localizedDescription)" }
        model.releaseBackground()
    }

    private func fix() async throws -> CLLocation {
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
            for _ in 0..<60 where mgr.authorizationStatus == .notDetermined { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        switch mgr.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: throw RelayError("Standortzugriff fehlt (Einstellungen, Relay, Standort)")
        }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<CLLocation, Error>) in
            cont = c
            mgr.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.finish(.failure(RelayError("kein Standort innerhalb von 60 s")))
            }
        }
    }

    private func finish(_ r: Result<CLLocation, Error>) {
        guard let c = cont else { return }
        cont = nil
        c.resume(with: r)
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in self.finish(.success(l)) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
