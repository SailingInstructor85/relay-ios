import Foundation
import SwiftUI
import UIKit
import Photos
import Network
import ImageIO
import UniformTypeIdentifiers
import RelayCore

/// Ein freigegebener Ordner aus der Dateien-App (auch Google Drive, wenn dort als Speicherort aktiv). Das Lesezeichen
/// mit Sicherheitsbereich erlaubt den Zugriff später ohne neuen Auswahldialog.
struct SharedFolder: Codable, Identifiable, Equatable {
    var name: String
    var display: String
    var bookmark: Data
    var id: String { name }
}

/// Fehler beim Ausführen, mit Fehlerwort für das Gateway.
struct PhoneFail: Error, LocalizedError {
    let code: PhoneCmdError
    let message: String
    init(_ code: PhoneCmdError, _ message: String) { self.code = code; self.message = message }
    var errorDescription: String? { message }
}

/// Telefonzugriff, Stufe 1 (docs/telefonzugriff.md): Agenten fragen über das Gateway (`phone_command`), Relay prüft
/// gegen Katalog und Schalter (`PhonePolicy`), führt Lesebefehle ohne Einzelbestätigung aus und antwortet mit
/// `phone_command_result`. Alles landet im Verlauf (30 Tage, ohne Inhalte). Der Not-Aus lehnt alles ab.
@MainActor
final class PhoneAccessStore: ObservableObject {
    static let shared = PhoneAccessStore()

    @Published private(set) var settings: PhoneSettings
    @Published private(set) var folders: [SharedFolder]
    @Published private(set) var log: [PhoneLogEntry]
    @Published private(set) var running: String?
    private var deferred: [PhoneCommand] = []   // warten auf den Vordergrund (Zwischenablage)
    private var handled: Set<String> = []
    private var active = 0
    private let net = NWPathMonitor()
    fileprivate var netKind = "unbekannt"

    private init() {
        let d = UserDefaults.standard
        let areas = Set((d.string(forKey: "phoneAreas") ?? "").split(separator: ",").compactMap { PhoneArea(rawValue: String($0)) })
        let f = Self.load([SharedFolder].self, "phone-folders.json") ?? []
        folders = f
        settings = PhoneSettings(killswitch: d.bool(forKey: "phoneKill"), areas: areas, folders: f.map(\.name))
        log = Self.load([PhoneLogEntry].self, "phone-log.json") ?? []
        net.pathUpdateHandler = { path in
            let k: String
            if path.status != .satisfied { k = "kein Netz" }
            else if path.usesInterfaceType(.wifi) { k = "WLAN" }
            else if path.usesInterfaceType(.cellular) { k = "Mobilfunk" }
            else if path.usesInterfaceType(.wiredEthernet) { k = "Kabel" }
            else { k = "anderes" }
            Task { @MainActor in PhoneAccessStore.shared.netKind = k }
        }
        net.start(queue: DispatchQueue(label: "relay.phone.net"))
    }

    // MARK: Schalter

    var statusLine: String {
        if settings.killswitch { return "Not-Aus an: alle Anfragen werden abgelehnt" }
        let on = PhoneArea.allCases.filter { settings.areas.contains($0) }.map(\.title)
        return on.isEmpty ? "Aus: kein Bereich freigegeben" : "Freigegeben: " + on.joined(separator: ", ")
    }

    func setKill(_ on: Bool) {
        settings.killswitch = on
        UserDefaults.standard.set(on, forKey: "phoneKill")
        UsageRecorder.shared.record("telefonzugriff", on ? "Not-Aus an" : "Not-Aus aus")
        if on {
            let waiting = deferred
            deferred = []
            for c in waiting { handled.insert(c.id); Task { await finish(c, started: Date().timeIntervalSince1970, .fail(.killswitch, "")) } }
        }
        Task { await pushCaps() }
    }

    func setArea(_ a: PhoneArea, _ on: Bool) {
        if on { settings.areas.insert(a) } else { settings.areas.remove(a) }
        UserDefaults.standard.set(PhoneArea.allCases.filter { settings.areas.contains($0) }.map(\.rawValue).joined(separator: ","), forKey: "phoneAreas")
        UsageRecorder.shared.record("telefonzugriff", "Bereich", detail: "\(a.rawValue) \(on ? "an" : "aus")")
        if on, a == .photos, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
        }
        Task { await pushCaps() }
    }

    func killBinding() -> Binding<Bool> { Binding(get: { self.settings.killswitch }, set: { self.setKill($0) }) }
    func areaBinding(_ a: PhoneArea) -> Binding<Bool> { Binding(get: { self.settings.areas.contains(a) }, set: { self.setArea(a, $0) }) }

    // MARK: Ordner

    func addFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let bm = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let name = FolderNames.make(url.lastPathComponent, existing: folders.map(\.name))
            let parent = url.deletingLastPathComponent().lastPathComponent
            folders.append(SharedFolder(name: name, display: parent.isEmpty ? url.lastPathComponent : "\(parent)/\(url.lastPathComponent)", bookmark: bm))
            foldersChanged()
            UsageRecorder.shared.record("telefonzugriff", "Ordner freigegeben")
        } catch {
            AppModel.shared.lastError = "Ordner nicht freigegeben: \(error.localizedDescription)"
        }
    }

    func rename(_ f: SharedFolder, to raw: String) {
        guard let i = folders.firstIndex(of: f) else { return }
        let name = FolderNames.make(raw, existing: folders.filter { $0 != f }.map(\.name))
        folders[i].name = name
        foldersChanged()
    }

    func remove(_ f: SharedFolder) {
        folders.removeAll { $0 == f }
        foldersChanged()
    }

    private func foldersChanged() {
        settings.folders = folders.map(\.name)
        Self.save(folders, "phone-folders.json")
        Task { await pushCaps() }
    }

    // MARK: Gateway

    /// Schalter ans Gateway, damit es Unerlaubtes gleich ablehnt.
    func pushCaps() async {
        guard AppModel.shared.isConnected else { return }
        _ = try? await AppModel.shared.rpc("phone_caps", settings.caps, timeout: 10)
    }

    /// Nach `hello_ok`: Schalter melden und offene Befehle abholen (auch die, die im Hintergrund kamen).
    func reconcile() async {
        await pushCaps()
        guard let r = try? await AppModel.shared.rpc("phone_command_pending", [:], timeout: 15) else { return }  // altes Gateway
        for c in r["commands"].array.compactMap(PhoneCommand.from) { handle(c) }
    }

    func onEvent(_ ev: JSON, replay: Bool) {
        switch ev.str("type") {
        case "phone_command":
            guard !replay, let c = PhoneCommand.from(ev) else { return }  // nachgespielte holt `reconcile` vollständig
            handle(c)
        case "phone_command_resolved":
            let id = ev.str("request_id")
            deferred.removeAll { $0.id == id }
        default: break
        }
    }

    /// Die App ist wieder vorn: was auf den Vordergrund wartete, läuft jetzt.
    func foregroundCame() {
        let waiting = deferred
        deferred = []
        for c in waiting { handle(c) }
    }

    /// Hintergrundabruf: höchstens `max` Sekunden warten, bis laufende Befehle fertig sind.
    func waitIdle(max: Double) async {
        let until = Date().addingTimeInterval(max)
        while active > 0 && Date() < until { try? await Task.sleep(nanoseconds: 250_000_000) }
    }

    private var isFront: Bool { AppModel.shared.isForeground && UIApplication.shared.applicationState == .active }

    func handle(_ c: PhoneCommand) {
        guard !handled.contains(c.id) else { return }
        let now = Date().timeIntervalSince1970
        switch PhonePolicy.decide(c, settings: settings, foreground: isFront, now: now, log: log) {
        case .waitForForeground:
            if !deferred.contains(where: { $0.id == c.id }) { deferred.append(c) }
        case .refuse(let e):
            handled.insert(c.id)
            Task { await finish(c, started: now, .fail(e, "")) }
        case .run:
            handled.insert(c.id)
            active += 1
            Task {
                await execute(c, started: now)
                active -= 1
            }
        }
    }

    // MARK: Ausführen

    private enum Outcome {
        case ok(JSON?, file: String?, detail: String)
        case fail(PhoneCmdError, String)
    }

    private func execute(_ c: PhoneCommand, started: Double) async {
        running = PhoneCatalog.title(c.name)
        defer { running = nil }
        let out: Outcome
        do {
            switch c.name {
            case "device_info":
                out = .ok(deviceInfo(), file: nil, detail: "")
            case "files_list":
                let (root, parts) = try folder(c)
                let items = try await Task.detached { try PhoneAccessStore.list(root: root, parts: parts) }.value
                out = .ok(.object(["items": .array(items)]), file: nil, detail: "\(items.count) Einträge")
            case "files_get":
                let (root, parts) = try folder(c)
                let (name, data) = try await Task.detached { try PhoneAccessStore.read(root: root, parts: parts, max: PhoneCatalog.maxFileBytes) }.value
                let path = try await AppModel.shared.upload(name: name, data: data)
                out = .ok(.object(["name": .string(name), "size": .number(Double(data.count))]), file: path, detail: "Datei, \(PhoneLog.size(data.count))")
            case "photos_recent":
                try await photosAllowed()
                let items = recentPhotos(c)
                out = .ok(.object(["items": .array(items)]), file: nil, detail: "\(items.count) Fotos")
            case "photos_get":
                try await photosAllowed()
                let (name, data) = try await photo(c)
                let path = try await AppModel.shared.upload(name: name, data: data)
                out = .ok(.object(["name": .string(name), "size": .number(Double(data.count))]), file: path, detail: "Foto, \(PhoneLog.size(data.count))")
            case "clipboard_get":
                guard isFront else { throw PhoneFail(.notInForeground, "Relay war nicht geöffnet") }
                let text = UIPasteboard.general.string ?? ""
                out = .ok(.object(["text": .string(text)]), file: nil, detail: "\(text.count) Zeichen")
            default:
                out = .fail(.unsupported, "")
            }
        } catch let e as PhoneFail {
            out = .fail(e.code, e.message)
        } catch {
            out = .fail(.failed, error.localizedDescription)
        }
        await finish(c, started: started, out)
    }

    private func finish(_ c: PhoneCommand, started: Double, _ out: Outcome) async {
        var p: [String: JSON] = ["request_id": .string(c.id)]
        let outcome: String, detail: String
        switch out {
        case .ok(let result, let file, let d):
            p["ok"] = true
            if let result { p["result"] = result }
            if let file { p["file"] = .string(file) }
            outcome = "done"; detail = d
        case .fail(let e, let msg):
            p["ok"] = false
            // ein freier Fehlertext kommt beim Gateway als „failed“ mit Erklärung an
            p["error"] = .string(e == .failed && !msg.isEmpty ? msg : e.rawValue)
            outcome = e.rawValue; detail = msg
        }
        let now = Date().timeIntervalSince1970
        var entry = PhoneLogEntry(id: c.id, ts: now, command: c.name, requestedBy: c.requestedBy, reason: c.reason,
                                  outcome: outcome, detail: detail, durationMs: Int((now - started) * 1000))
        UsageRecorder.shared.record("telefonzugriff", c.name, detail: outcome, error: outcome == "done" ? nil : detail)
        do {
            if !AppModel.shared.isConnected { _ = await AppModel.shared.connectOnce(timeout: 15) }
            _ = try await AppModel.shared.rpc("phone_command_result", .object(p), timeout: 30)
        } catch {
            entry.detail = [detail, "Antwort nicht zugestellt"].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        log = PhoneLog.add(entry, to: log, now: now)
        Self.save(log, "phone-log.json")
    }

    // MARK: Geräteinfos

    private func deviceInfo() -> JSON {
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        let st = dev.batteryState
        let charging: Bool? = st == .unknown ? nil : (st == .charging || st == .full)
        let vals = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        var u = utsname()
        uname(&u)
        let model = withUnsafePointer(to: &u.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return DeviceInfo.json(battery: dev.batteryLevel, charging: charging, freeBytes: vals?.volumeAvailableCapacityForImportantUsage,
                               totalBytes: vals?.volumeTotalCapacity.map { Int64($0) }, ios: dev.systemVersion, model: model,
                               app: app, network: netKind)
    }

    // MARK: Ordner lesen

    private func folder(_ c: PhoneCommand) throws -> (URL, [String]) {
        guard let f = folders.first(where: { $0.name == c.string("folder") }) else { throw PhoneFail(.notAllowed, "Ordner nicht freigegeben") }
        guard let parts = PhonePaths.components(c.string("path")) else { throw PhoneFail(.notAllowed, "Pfad außerhalb des Ordners") }
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: f.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw PhoneFail(.failed, "Ordner „\(f.name)“ nicht mehr erreichbar, bitte neu freigeben") }
        if stale, let i = folders.firstIndex(of: f) {
            let ok = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                folders[i].bookmark = fresh
                Self.save(folders, "phone-folders.json")
            }
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        return (url, parts)
    }

    nonisolated private static func target(_ root: URL, _ parts: [String]) -> URL {
        parts.reduce(root) { $0.appendingPathComponent($1) }
    }

    /// Inhalt eines Ordners (höchstens 500 Einträge), koordiniert gelesen, damit Cloud-Anbieter mitspielen.
    nonisolated private static func list(root: URL, parts: [String]) throws -> [JSON] {
        let ok = root.startAccessingSecurityScopedResource()
        defer { if ok { root.stopAccessingSecurityScopedResource() } }
        let dir = target(root, parts)
        var out: [JSON] = []
        var coordErr: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: [], error: &coordErr) { u in
            do {
                let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                let items = try FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
                for i in items.prefix(500) {
                    let v = try? i.resourceValues(forKeys: Set(keys))
                    var o: [String: JSON] = ["name": .string(i.lastPathComponent), "dir": .bool(v?.isDirectory ?? false)]
                    if let s = v?.fileSize { o["size"] = .number(Double(s)) }
                    if let d = v?.contentModificationDate { o["modified"] = .number(d.timeIntervalSince1970) }
                    out.append(.object(o))
                }
            } catch { inner = error }
        }
        if let e = coordErr { throw e }
        if let e = inner { throw e }
        return out.sorted { $0.str("name").localizedStandardCompare($1.str("name")) == .orderedAscending }
    }

    /// Eine Datei (höchstens `max` Byte); Dateien nur in der Cloud lädt iOS dabei nach.
    nonisolated private static func read(root: URL, parts: [String], max: Int) throws -> (String, Data) {
        guard !parts.isEmpty else { throw PhoneFail(.failed, "Pfad zur Datei fehlt") }
        let ok = root.startAccessingSecurityScopedResource()
        defer { if ok { root.stopAccessingSecurityScopedResource() } }
        let file = target(root, parts)
        var result: (String, Data)?
        var coordErr: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordErr) { u in
            do {
                let v = try u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if v.isDirectory == true { throw PhoneFail(.failed, "Das ist ein Ordner, files_list nehmen") }
                if let s = v.fileSize, s > max { throw PhoneFail(.failed, "Datei zu groß (\(PhoneLog.size(s)), höchstens \(PhoneLog.size(max)))") }
                result = (u.lastPathComponent, try Data(contentsOf: u))
            } catch { inner = error }
        }
        if let e = coordErr { throw e }
        if let e = inner { throw e }
        guard let r = result else { throw PhoneFail(.failed, "Datei nicht lesbar") }
        return r
    }

    // MARK: Fotos

    private func photosAllowed() async throws {
        var st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .notDetermined {
            guard isFront else { throw PhoneFail(.notInForeground, "Fotozugriff muss einmal bei geöffneter App erlaubt werden") }
            st = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard st == .authorized || st == .limited else { throw PhoneFail(.notAllowed, "Fotozugriff ist in den iOS-Einstellungen aus") }
    }

    private func recentPhotos(_ c: PhoneCommand) -> [JSON] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = PhoneCatalog.photoCount(c)
        if let since = c.args["since"]?.double {
            opts.predicate = NSPredicate(format: "creationDate > %@", Date(timeIntervalSince1970: since) as NSDate)
        }
        var items: [JSON] = []
        PHAsset.fetchAssets(with: .image, options: opts).enumerateObjects { a, _, _ in
            var o: [String: JSON] = ["id": .string(a.localIdentifier), "width": .number(Double(a.pixelWidth)),
                                     "height": .number(Double(a.pixelHeight)), "favorite": .bool(a.isFavorite)]
            if let d = a.creationDate { o["date"] = .number(d.timeIntervalSince1970) }
            if let l = a.location {
                o["lat"] = .number((l.coordinate.latitude * 1000).rounded() / 1000)
                o["lon"] = .number((l.coordinate.longitude * 1000).rounded() / 1000)
            }
            items.append(.object(o))
        }
        return items
    }

    private func photo(_ c: PhoneCommand) async throws -> (String, Data) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [c.string("id")], options: nil).firstObject else {
            throw PhoneFail(.failed, "Foto nicht gefunden")
        }
        let raw: Data = try await withCheckedThrowingContinuation { cont in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .highQualityFormat
            o.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: o) { d, _, _, info in
                if let d { cont.resume(returning: d) }
                else { cont.resume(throwing: PhoneFail(.failed, (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "Foto nicht lesbar")) }
            }
        }
        let edge = PhoneCatalog.maxPx(c)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: edge]
        guard let src = CGImageSourceCreateWithData(raw as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { throw PhoneFail(.failed, "Foto nicht umwandelbar") }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return ("foto-\(f.string(from: asset.creationDate ?? Date())).jpg", jpg)
    }

    // MARK: Ablage

    private static func url(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private static func load<T: Decodable>(_ t: T.Type, _ name: String) -> T? {
        guard let u = url(name), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }

    private static func save<T: Encodable>(_ v: T, _ name: String) {
        guard let u = url(name), let d = try? JSONEncoder().encode(v) else { return }
        try? d.write(to: u, options: .atomic)
    }
}

// MARK: - Ansichten

/// Einstellungen → Telefonzugriff: Not-Aus, Verlauf, Bereiche, Ordner.
struct PhoneAccessView: View {
    @ObservedObject private var store = PhoneAccessStore.shared
    @State private var picking = false
    @State private var renaming: SharedFolder?
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                Toggle("Not-Aus: alles ablehnen", isOn: store.killBinding()).accessibilityIdentifier("phoneKill")
                Text("An: Relay lehnt jede Anfrage eines Agenten ab, offene Anfragen auch. Die Bereiche unten bleiben gespeichert.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Not-Aus") }
            Section("Verlauf") {
                NavigationLink { PhoneLogView() } label: {
                    HStack { Text("Anfragen der Agenten"); Spacer(); Text("\(store.log.count)").foregroundStyle(.secondary) }
                }.accessibilityIdentifier("phoneLog")
                if let r = store.running { Label("Läuft: \(r)", systemImage: "hourglass").font(.caption) }
            }
            Section {
                ForEach(PhoneArea.allCases, id: \.self) { a in
                    Toggle(isOn: store.areaBinding(a)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title)
                            Text(a.help).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("phoneArea-\(a.rawValue)")
                }
            } header: { Text("Bereiche") } footer: {
                Text("Lesen in einem eingeschalteten Bereich läuft ohne Rückfrage, jede Anfrage steht im Verlauf. Kalender, Kontakte und Schreiben gibt es noch nicht.")
            }
            Section {
                ForEach(store.folders) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(.body.monospaced())
                        Text(f.display).font(.caption).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Umbenennen") { newName = f.name; renaming = f }
                        Button("Freigabe entfernen", role: .destructive) { store.remove(f) }
                    }
                    .swipeActions { Button("Entfernen", role: .destructive) { store.remove(f) } }
                }
                Button { picking = true } label: { Label("Ordner freigeben…", systemImage: "folder.badge.plus") }
                    .accessibilityIdentifier("phoneAddFolder")
            } header: { Text("Ordner") } footer: {
                Text("Agenten nennen den Ordner beim kurzen Namen. Google Drive erscheint in der Auswahl, wenn die Google-Drive-App installiert und in der Dateien-App als Speicherort aktiv ist. Keine Zugangsdaten in Relay.")
            }
        }
        .navigationTitle("Telefonzugriff")
        .onAppear { UsageRecorder.shared.screen("telefonzugriff") }
        .sheet(isPresented: $picking) { FolderPicker { url in Task { @MainActor in PhoneAccessStore.shared.addFolder(url) } }.ignoresSafeArea() }
        .alert("Kurzer Name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Sichern") { if let f = renaming { store.rename(f, to: newName) }; renaming = nil }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        } message: { Text("So nennt ein Agent den Ordner, zum Beispiel „scans“.") }
    }
}

/// Telefonzugriff → Verlauf: jede Anfrage mit Zeit, Agent, Grund und Ergebnis (30 Tage, ohne Inhalte).
struct PhoneLogView: View {
    @ObservedObject private var store = PhoneAccessStore.shared

    var body: some View {
        List {
            if store.log.isEmpty {
                Text("Noch keine Anfragen.").foregroundStyle(.secondary)
            }
            ForEach(store.log) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(PhoneCatalog.title(e.command)).font(.body.weight(.semibold))
                        Spacer()
                        Text(e.ts.formattedTime).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(PhoneLog.outcomeText(e.outcome)).font(.caption).foregroundStyle(e.ok ? Color.green : Color.orange)
                    Text([e.requestedBy, e.reason].filter { !$0.isEmpty }.joined(separator: ": ")).font(.caption).foregroundStyle(.secondary)
                    if !e.detail.isEmpty { Text(e.detail).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Verlauf")
    }
}

private extension Double {
    /// „07.11. 21:14“
    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm"
        return f.string(from: Date(timeIntervalSince1970: self))
    }
}

/// Auswahldialog für einen Ordner (Dateien-App).
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        p.allowsMultipleSelection = false
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(_ f: @escaping (URL) -> Void) { onPick = f }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) }
        }
    }
}
