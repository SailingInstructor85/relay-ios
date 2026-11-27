import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RelayCore

/// Ein Foto oder Dokument, das im Jarvis-Chat angehängt ist und mit der nächsten Nachricht hochgeladen wird: eine Datei
/// aus der Dateien-App, ein Kamerafoto oder ein Bild aus der Zwischenablage (Bytes) oder ein Foto, Screenshot oder Video
/// aus der Mediathek (`StagedMedia`).
struct JarvisDoc: Identifiable {
    let id = UUID()
    let name: String
    let data: Data?
    let media: StagedMedia?
    /// Vorschaubild für Bilder, die als Bytes kommen (Kamera, Zwischenablage, Bilddatei).
    var preview: UIImage? = nil

    /// Das Vorschaubild der Marke über der Eingabe; nil bei Dokumenten ohne Bild.
    var thumb: UIImage? { preview ?? media?.thumb }

    func bytes() -> Data? { data ?? media?.bytes() }
    func discard() { media?.discard() }
}

/// Jarvis, the overview agent on the Desktop (rpc `ask`, streamed). By voice: tap the microphone, speak, the answer is
/// read aloud sentence by sentence; in conversation mode it listens again after each answer until nothing is said.
struct JarvisView: View {
    @EnvironmentObject var model: AppModel
    /// Nachrichten, die ohne Verbindung geschrieben oder eingesprochen wurden, warten in der Outbox (`JarvisOutbox`).
    @ObservedObject private var outbox = Outbox.shared
    /// Die angetippte wartende Nachricht („Jetzt senden“, „Bearbeiten“, „Löschen“).
    @State private var acting: OutItem?
    var autoListen = false
    /// Eine Frage, die beim Öffnen sofort gestellt wird (Eingabeleiste auf „Heute“).
    var initialQuestion: String?
    /// Was für `initialQuestion` im Verlauf steht (Dokumente aus dem Teilen-Blatt: Nachricht und Dateinamen statt des
    /// ganzen Auftrags mit Pfaden); nil = die Frage selbst.
    var initialShown: String?
    @State private var askedInitial = false

    /// Ein Zug im Verlauf. `topic` und `ref` nur bei Rückmeldungen, die der Chief von sich aus schreibt (`JarvisSay`);
    /// `status`: was unter der Frage steht, solange die Antwort aussteht („Chief hat es“).
    struct Turn: Identifiable {
        var id = UUID(); let q: String; var a: String; var done: Bool; let voice: Bool; var ts = Date().timeIntervalSince1970
        var topic: String? = nil; var ref: String? = nil; var status = ""

        static func from(_ t: JarvisTurn) -> Turn { Turn(id: t.id, q: t.q, a: t.a, done: true, voice: t.voice, ts: t.ts, topic: t.topic, ref: t.ref) }
        var stored: JarvisTurn { JarvisTurn(id: id, q: q, a: a, voice: voice, ts: ts, topic: topic, ref: ref) }
    }
    @State private var turns: [Turn] = []
    @State private var input = ""
    /// Fragen, deren Antwort noch aussteht. Sie sperren das Feld nicht: Die nächste Nachricht geht sofort raus.
    @State private var pending = 0
    /// Gerade werden angehängte Dokumente hochgeladen: Bis sie am PC sind, geht nichts Neues raus.
    @State private var asking = false
    /// Rückmeldungen, die noch vorzulesen sind, sobald weder gesprochen noch zugehört wird.
    @State private var toSpeak: [String] = []
    @State private var error: String?
    @State private var voiceTask: Task<Void, Never>?
    /// How the running recording is to end: a pause (ask right away), the stop button (into the field), send.
    @State private var endedBy: JarvisDictation.End = .pause
    @StateObject private var voice = VoiceIO()
    @AppStorage("jarvisSpeak") private var speakAnswers = true
    @AppStorage("jarvisConversation") private var conversation = true
    @AppStorage(SpeechPrefs.recogKey) private var recog = "auto"
    @FocusState private var inputFocused: Bool
    @State private var teaching = false
    @State private var confirmClear = false
    /// Füllstand des Gesprächs am PC (RPC `jarvis_context`); nil, solange das Gateway ihn nicht liefert.
    @State private var context: JarvisContext.Status?
    /// Führt am PC der Chief das Gespräch (RPC `jarvis_context` mit `lead`), lässt er sich hier auf Zuruf ablösen.
    @State private var lead: JarvisContext.Lead?
    @State private var confirmHandOver = false
    /// Wann hier „Neues Gespräch beginnen“ getippt wurde (für die Trennlinie im Verlauf).
    @State private var resets: [Double] = JarvisResets.load()
    @State private var notice: String?
    /// Angehängte Dokumente: Sie gehen mit der nächsten Nachricht (getippt oder gesprochen) an den PC und zu Jarvis.
    @State private var docs: [JarvisDoc] = []
    @State private var importing = false
    @State private var pickingPhoto = false
    @State private var camera = false
    @State private var uploading = ""
    /// Ob der Verlauf seinem Ende folgt (`ChatScroll`). In einer Ablage ohne Beobachtung: Jede Scrollbewegung meldet
    /// sich hier, und nur wenn der Knopf erscheint oder verschwindet, baut sich die Ansicht neu auf.
    @State private var scrollBox = JarvisScrollBox()
    /// Der Knopf „Ans Ende springen“ ist zu sehen (es wurde hochgescrollt).
    @State private var showJump = false

    private static let endID = "jarvisEnd"
    private static let scrollSpace = "jarvisScroll"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.voiceLive {
                            Label("Der Desktop bietet Jarvis Live an. Das braucht den Sprachkanal des PCs und gibt es in dieser App nicht. Relay nutzt hier die Spracherkennung des iPhones.", systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        if turns.isEmpty && waiting.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(JarvisDictation.intro, systemImage: "info.circle").font(.callout)
                                    .accessibilityIdentifier("jarvisIntro")
                                Text(JarvisDictation.howTo).font(.callout).foregroundStyle(.secondary)
                            }.padding()
                        }
                        let breaks = JarvisContext.breaks(times: turns.map(\.ts), resets: resets)
                        ForEach(Array(turns.enumerated()), id: \.element.id) { i, t in
                            // hier hat am PC ein neues Gespräch begonnen (neuer Tag ab 4 Uhr oder zurückgesetzt)
                            if breaks.contains(i) { contextBreak(JarvisContext.breakLabel) }
                            VStack(alignment: .leading, spacing: 6) {
                                if let topic = t.topic {
                                    // eine Rückmeldung, die der Chief von sich aus schreibt: das Thema als Überschrift
                                    Label(topic, systemImage: "text.bubble").font(.headline)
                                        .accessibilityIdentifier("jarvisSayTopic")
                                } else {
                                    HStack {
                                        Spacer()
                                        if t.voice { Image(systemName: "waveform").font(.caption).foregroundStyle(.secondary) }
                                        Text(t.q).textSelection(.enabled).padding(10).background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                                // Antwort mit markierbarem Text: langes Drücken setzt die Griffe, Teile lassen sich einzeln kopieren
                                if t.a.isEmpty && !t.done {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        // der Chief hat die Nachricht, die Antwort kommt noch
                                        if !t.status.isEmpty {
                                            Text(t.status).font(.footnote).foregroundStyle(.secondary)
                                                .accessibilityIdentifier("jarvisTaken")
                                        }
                                    }
                                } else { MarkdownText(text: t.a, marking: true).font(RelayFont.reply).lineSpacing(3) }
                            }.padding(.horizontal).id(t.id)
                        }
                        waitingRows
                        if pending == 0, JarvisContext.breakPending(last: turns.last?.ts, now: Date().timeIntervalSince1970, resets: resets) {
                            contextBreak(JarvisContext.nextBreakLabel)
                        }
                        if voice.listening {
                            HStack { Spacer(); Text(voice.partial.isEmpty ? "Ich höre…" : voice.partial).italic().foregroundStyle(.secondary).padding(10) }
                                .padding(.horizontal).id("partial")
                        }
                        // feste Marke am Ende: Dorthin wird gescrollt, nicht zu einer Zeile, die es eben erst gibt
                        Color.clear.frame(height: 1).id(Self.endID)
                    }.padding(.vertical)
                    // Lage und Höhe des Inhalts im Scrollbereich: daraus ergibt sich, ob hochgescrollt ist
                    .background(GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named(Self.scrollSpace)), initial: true) { _, f in scrolled(f) }
                    })
                }
                .coordinateSpace(name: Self.scrollSpace)
                // Höhe des sichtbaren Ausschnitts; wird er kleiner (Tastatur, Hinweiszeile), bleibt das Ende im Bild
                .background(GeometryReader { g in
                    Color.clear.onChange(of: g.size.height, initial: true) { _, h in
                        scrollBox.viewport = Double(h)
                        follow(proxy)
                    }
                })
                // nur wenn hochgescrollt ist: runder Knopf rechts unten über dem Verlauf, ein Tipp scrollt ans Ende
                .overlay(alignment: .bottomTrailing) { if showJump { jumpButton(proxy) } }
                // Neuer Inhalt (eigene Nachricht, einlaufende Antwort, Rückmeldung, wartende Nachricht, Diktat): ans
                // Ende, solange man vorher unten war. Wer hochgescrollt hat, bleibt dort stehen.
                .onChange(of: turns.last?.a) { _, _ in follow(proxy) }
                .onChange(of: turns.count) { _, _ in follow(proxy) }
                .onChange(of: waiting.count) { _, _ in follow(proxy) }
                .onChange(of: voice.partial) { _, _ in follow(proxy) }
                .onChange(of: voice.listening) { _, _ in follow(proxy) }
            }
            if let e = error { ErrorBanner(text: Binding(get: { e }, set: { error = $0 })).padding(.vertical, 4) }
            if let n = notice {
                Text(n).font(.footnote).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 4)
                    .accessibilityIdentifier("jarvisNotice")
            }
            if let p = JarvisAsk.pendingLabel(pending) {
                Text(p).font(.footnote).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 2)
                    .accessibilityIdentifier("jarvisPending")
            }
            micBar
            if !uploading.isEmpty { Text(uploading).font(.caption).foregroundStyle(.secondary).padding(.bottom, 4) }
            if !docs.isEmpty { docStrip }
            HStack {
                // Fotos und Dokumente in den Chat geben: Jarvis bekommt sie mit der nächsten Nachricht und gibt sie weiter.
                // Reihenfolge wie im Sitzungs-Chat, Fotos (mit Screenshots aus der Mediathek) zuerst.
                Menu {
                    // A picker inside a Menu does not open on iOS; a moment later the menu has closed (as in the chat).
                    Button { Task { try? await Task.sleep(nanoseconds: 350_000_000); pickingPhoto = true } } label: { Label("Fotos, Screenshots oder Videos", systemImage: "photo.on.rectangle") }
                    if CameraPicker.available { Button { camera = true } label: { Label("Kamera", systemImage: "camera") } }
                    if UIPasteboard.general.hasImages { Button { Task { await addClipboard() } } label: { Label("Bild aus Zwischenablage", systemImage: "doc.on.clipboard") } }
                    Button { importing = true } label: { Label("Datei", systemImage: "doc") }
                } label: { Image(systemName: "paperclip").font(.title3) }
                    .disabled(asking)
                    .accessibilityLabel("Fotos oder Dokumente anhängen").accessibilityIdentifier("jarvisAttach")
                TextField(docs.isEmpty ? "Jarvis schreiben…" : "Was soll Jarvis damit tun?", text: $input, axis: .vertical).lineLimit(1...4)
                    .focused($inputFocused).accessibilityIdentifier("jarvisInput")
                    .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button { sendTapped() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }.disabled(!(JarvisDictation.canSend(typed: input, listening: voice.listening, partial: voice.partial, asking: asking)
                             || JarvisDocs.canSend(docs: docs.count, asking: asking)))
                    .accessibilityLabel("Senden").accessibilityIdentifier("jarvisSend")
            }.padding([.horizontal, .bottom])
        }
        .background { RelayColor.background.ignoresSafeArea() }
        .toolbarBackground(RelayColor.background, for: .navigationBar)
        .navigationTitle("Jarvis")
        .onAppear { UsageRecorder.shared.screen("jarvis") }
        // Getipptes und während eines Diktats Erkanntes übersteht Absturz und Beenden der App (`Drafts`)
        .keepsDraft(Drafts.jarvis, text: $input, heard: voice.listening ? voice.partial : "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $speakAnswers) { Label("Antworten vorlesen", systemImage: "speaker.wave.2") }
                    Toggle(isOn: $conversation) { Label("Gesprächsmodus", systemImage: "bubble.left.and.bubble.right") }
                    Picker(selection: $recog) {
                        Text("Automatisch").tag("auto")
                        Text("Deutsch").tag("de")
                        Text("English").tag("en")
                    } label: { Label("Sprache der Erkennung", systemImage: "globe") }
                    Button { teaching = true } label: { Label("Erkennung korrigieren", systemImage: "character.book.closed") }
                    // nur wenn das Gateway den Füllstand liefert (dann kennt es auch das Zurücksetzen)
                    if let c = context {
                        Section(JarvisContext.fillLabel(c)) {
                            Button { Task { await resetContext() } } label: { Label(JarvisContext.resetLabel, systemImage: "arrow.counterclockwise") }
                                .disabled(asking || pending > 0)
                        }
                    }
                    // der Chief führt das Gespräch: Ablösung auf Zuruf (er schreibt seine Notizen, dann beginnt eine frische Sitzung)
                    if let l = lead {
                        Section(JarvisContext.leadLabel(l)) {
                            // die Nachfrage öffnet einen Moment später, sonst geht sie mit dem schließenden Menü verloren
                            Button { Task { try? await Task.sleep(nanoseconds: 350_000_000); confirmHandOver = true } } label: { Label(JarvisContext.handOverLabel(l.name), systemImage: "arrow.triangle.2.circlepath") }
                        }
                    }
                    Button(role: .destructive) { confirmClear = true } label: { Label("Chat löschen", systemImage: "trash") }
                        .disabled(turns.isEmpty)
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .task {
            turns = JarvisStore.load().map(Turn.from)
            model.warmJarvis()
            if let q = initialQuestion, !askedInitial {
                askedInitial = true
                UsageRecorder.shared.content("jarvis", "gesendet", session: nil, kind: initialShown == nil ? "text" : "datei", text: initialShown ?? q)
                // aus „Teilen“ kommt die Frage immer mit hochgeladenen Dateien (initialShown gesetzt): ein Upload
                Task { await ask(q, byVoice: false, shown: initialShown, upload: initialShown != nil) }
            }
            await loadVocab()
            if autoListen { startVoice(trigger: "mic") }
            await loadContext()
        }
        .onChange(of: inputFocused) { _, focused in if focused { model.warmJarvis() } }
        .onAppear { JarvisInbox.shared.visible = true }
        .onDisappear { JarvisInbox.shared.visible = false; stopVoice() }
        .onChange(of: voice.speaking) { _, s in if !s { if toSpeak.isEmpty { releaseIfDone() } else { speakPending() } } }
        .onChange(of: voice.listening) { _, l in if !l { speakPending() } }
        // eine Rückmeldung des Chiefs ist eingetroffen (`jarvis_say`): in den Verlauf und vorlesen
        .onReceive(JarvisInbox.shared.$tick.dropFirst()) { _ in takeSays() }
        .sheet(isPresented: $teaching) { TeachRecognitionView(voice: voice) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoLibraryPicker { providers in
                pickingPhoto = false
                if !providers.isEmpty { Task { await addPicked(providers) } }
            }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                camera = false
                if let img, let d = img.jpegData(compressionQuality: 0.95) { Task { await addCamera(d) } }
            }.ignoresSafeArea()
        }
        .confirmationDialog("Den Jarvis-Verlauf auf diesem iPhone löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Chat löschen", role: .destructive) { turns = []; JarvisStore.clear() }
        }
        .confirmationDialog(JarvisContext.handOverTitle(lead?.name ?? ""), isPresented: $confirmHandOver, titleVisibility: .visible) {
            Button(JarvisContext.handOverConfirm) { Task { await handOver() } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text(JarvisContext.handOverMessage(lead?.name ?? "")) }
    }

    private var micBar: some View {
        HStack(spacing: 16) {
            // nur solange vorgelesen wird: bricht sofort ab, auch der Rest einer noch eintreffenden Antwort bleibt stumm
            if voice.speaking {
                Button { stopReading() } label: {
                    Label("Vorlesen stoppen", systemImage: "stop.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                .accessibilityIdentifier("jarvisStopSpeaking")
                .transition(.opacity)
            }
            Button { micTapped() } label: {
                Image(systemName: voice.listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(voice.listening ? .red : Color.accentColor)
                    .symbolEffect(.pulse, isActive: voice.listening)
            }
            .disabled(asking && voiceTask == nil)
            .accessibilityLabel(voice.listening ? "Zuhören beenden" : "Sprechen")
            .accessibilityIdentifier("jarvisMic")
        }
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.15), value: voice.speaking)
    }

    // MARK: Ende des Verlaufs

    /// Der Inhalt hat sich im Scrollbereich bewegt oder seine Höhe geändert.
    private func scrolled(_ f: CGRect) {
        scrollBox.scroll.moved(offset: Double(-f.minY), content: Double(f.height), viewport: scrollBox.viewport)
        let show = scrollBox.scroll.showsJump
        if show != showJump { showJump = show }
    }

    /// Ans Ende, wenn der Verlauf dem Ende folgt. Erst im nächsten Durchlauf und ohne Animation: Die neue Zeile ist
    /// dann gesetzt. Vorher wurde sofort zur eben erst eingefügten Zeile gescrollt, deren Lage noch nicht feststand;
    /// dabei konnte der Verlauf weit nach oben springen (Martin, 27.11.2026).
    private func follow(_ proxy: ScrollViewProxy) {
        guard scrollBox.scroll.follows else { return }
        DispatchQueue.main.async { proxy.scrollTo(Self.endID, anchor: .bottom) }
    }

    private func jumpButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            scrollBox.scroll.jump()
            showJump = false
            UsageRecorder.shared.record("jarvis", "ans ende gesprungen")
            withAnimation { proxy.scrollTo(Self.endID, anchor: .bottom) }
        } label: {
            Image(systemName: "arrow.down").font(.headline)
                .foregroundStyle(RelayColor.onSurfaceVariant)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .overlay { Circle().strokeBorder(RelayColor.outlineVariant, lineWidth: 1) }
                .frame(minWidth: KeyboardBar.minTapSize, minHeight: KeyboardBar.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12).padding(.bottom, 8)
        .accessibilityLabel(ChatScroll.jumpLabel).accessibilityIdentifier("jarvisJumpEnd")
        .transition(.opacity)
    }

    /// „Vorlesen stoppen“: nur die Sprachausgabe endet. Im Gesprächsmodus hört Jarvis danach wie gewohnt zu, so kann man
    /// gleich die nächste Frage stellen; der große Knopf beendet das Gespräch.
    private func stopReading() {
        UsageRecorder.shared.record("jarvis", "vorlesen gestoppt", kind: "vorlesen")
        voice.stopSpeaking()
    }

    // MARK: Dokumente

    /// Die angehängten Fotos und Dokumente über der Eingabe (`DocStrip`, derselbe Streifen wie im Antwortfeld einer Rückfrage).
    private var docStrip: some View {
        DocStrip(docs: docs, disabled: asking) { removeDoc($0) }
            .padding(.bottom, 6)
            .accessibilityIdentifier("jarvisDocs")
    }

    private func removeDoc(_ id: UUID) {
        docs.first(where: { $0.id == id })?.discard()
        docs.removeAll { $0.id == id }
    }

    private func attached(_ new: [JarvisDoc], kind: String) {
        guard !new.isEmpty else { return }
        docs += new
        UsageRecorder.shared.record("jarvis", "dokument angehängt", kind: kind, length: new.count)
    }

    /// Annehmen über `DocIntake`, gemeinsam mit dem Antwortfeld einer Rückfrage. Hochgeladen wird erst beim Senden.
    private func took(_ r: DocIntake.Loaded, kind: String) {
        attached(r.docs, kind: kind)
        if let e = r.error { error = e }
    }

    /// Dateien aus der Dateien-App: sofort lesen (der Zugriff gilt nur jetzt).
    private func addFiles(_ urls: [URL]) {
        took(DocIntake.files(urls), kind: "datei")
    }

    /// Fotos und Videos aus der Mediathek (Fotos schon auf 2048 px verkleinert, Videos bleiben in ihrer Datei).
    private func addPicked(_ providers: [NSItemProvider]) async {
        uploading = providers.count > 1 ? "Lade \(providers.count) Fotos aus der Mediathek…" : "Lade Auswahl…"
        let r = await DocIntake.picked(providers)
        uploading = ""
        took(r, kind: "foto")
    }

    private func addCamera(_ jpeg: Data) async {
        let r = await DocIntake.camera(jpeg)
        took(r, kind: "foto")
    }

    /// Ein Bild aus der Zwischenablage, zum Beispiel ein eben kopierter Screenshot.
    private func addClipboard() async {
        let r = await DocIntake.clipboard()
        took(r, kind: "zwischenablage")
    }

    /// Senden: ohne Dokumente die Frage wie bisher. Mit Dokumenten gehen sie zuerst an den PC, dann bekommt Jarvis die
    /// Pfade mit dem Auftrag (`JarvisDocs.prompt`); im Verlauf stehen Nachricht und Dateinamen. Scheitert ein Upload,
    /// bleiben Dokumente und Text stehen.
    /// Ohne Verbindung wartet alles in der Outbox, die Anhänge in ihrer Dateiablage auf dem iPhone (`queue`).
    /// Ergebnis: true, wenn die Antwort jetzt da ist; false, wenn die Nachricht wartet oder etwas scheiterte.
    @discardableResult
    private func submit(_ text: String, byVoice: Bool, trigger: String? = nil, t0: Date? = nil) async -> Bool {
        guard !docs.isEmpty else { return await ask(text, byVoice: byVoice, trigger: trigger, t0: t0) }
        let batch = docs
        // eine stille Verbindung kann tot sein (Flugmodus, PC schläft): erst prüfen, dann hochladen
        asking = true
        uploading = "Prüfe die Verbindung…"
        let alive = await model.ensureAlive()
        uploading = ""
        asking = false
        if !alive {
            var stored: [String] = []
            for d in batch {
                guard let data = d.bytes(), data.count <= JarvisDocs.maxBytes, let name = Outbox.storeFile(name: d.name, data: data) else {
                    stored.forEach { Outbox.dropFile($0) }
                    self.error = JarvisDocs.unreadable(d.name)
                    if input.isEmpty { input = text }
                    return false
                }
                stored.append(name)
            }
            batch.forEach { $0.discard() }
            docs.removeAll { d in batch.contains { $0.id == d.id } }
            queue(text.trimmingCharacters(in: .whitespacesAndNewlines), byVoice: byVoice, files: stored)
            return false
        }
        var paths: [String] = []
        asking = true
        do {
            for (i, d) in batch.enumerated() {
                uploading = JarvisDocs.progress(index: i, count: batch.count, name: d.name)
                guard let data = d.bytes() else { throw RelayError(JarvisDocs.unreadable(d.name)) }
                guard data.count <= JarvisDocs.maxBytes else { throw RelayError(JarvisDocs.tooBig(d.name)) }
                paths.append(try await model.upload(name: d.name, data: data))
            }
        } catch {
            uploading = ""
            asking = false
            self.error = error.localizedDescription
            if input.isEmpty { input = text }
            UsageRecorder.shared.record("jarvis", "dokument fehlgeschlagen", kind: "datei", error: error.localizedDescription)
            return false
        }
        uploading = ""
        asking = false
        batch.forEach { $0.discard() }
        docs.removeAll { d in batch.contains { $0.id == d.id } }
        UsageRecorder.shared.record("jarvis", "dokument gesendet", kind: "datei", length: batch.count)
        return await ask(JarvisDocs.prompt(message: text, paths: paths, vault: model.vaultDir), byVoice: byVoice, trigger: trigger, t0: t0,
                         shown: JarvisDocs.shown(message: text, names: batch.map(\.name)), upload: true)
    }

    // MARK: Warteschlange ohne Verbindung

    private var waiting: [OutItem] { outbox.items(for: JarvisOutbox.key) }

    /// Die Nachricht wartet auf dem iPhone und geht von selbst an Jarvis, sobald die Verbindung steht (auch nach
    /// einem Neustart der App). `files`: Anhänge in der Dateiablage der Outbox.
    private func queue(_ q: String, byVoice: Bool, shown: String? = nil, upload: Bool = false, files: [String] = []) {
        notice = nil
        Outbox.shared.add(key: JarvisOutbox.key, text: q, files: files, voice: byVoice, shown: shown, upload: upload)
        UsageRecorder.shared.record("jarvis", "in postausgang", kind: byVoice ? "diktat" : (files.isEmpty ? "text" : "datei"), length: q.count)
        if byVoice && speakAnswers { voice.speak(JarvisOutbox.spokenQueued) }
    }

    /// Wartende Nachrichten unter dem Verlauf: grau, mit ihrem Stand („wartet auf Verbindung“). Antippen bietet
    /// „Jetzt senden“, „Bearbeiten“ und „Löschen“ an.
    @ViewBuilder private var waitingRows: some View {
        let list = waiting
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(list) { i in waitingRow(i).id(i.id) }
            }
            .confirmationDialog(JarvisOutbox.menuTitle, isPresented: Binding(get: { acting != nil }, set: { if !$0 { acting = nil } }),
                                titleVisibility: .visible, presenting: acting) { i in
                Button(i.state == .failed ? JarvisOutbox.sendAgain : JarvisOutbox.sendNow) { sendNow(i) }
                if JarvisOutbox.editable(i) { Button(JarvisOutbox.edit) { editWaiting(i) } }
                Button(JarvisOutbox.delete, role: .destructive) { deleteWaiting(i) }
                Button("Abbrechen", role: .cancel) {}
            } message: { i in
                Text(JarvisOutbox.shownText(i))
            }
        }
    }

    private func waitingRow(_ i: OutItem) -> some View {
        let connected = model.state == .connected
        let status = JarvisOutbox.status(i, connected: connected, network: model.state != .noNetwork, taken: outbox.jarvisTaken[i.id])
        return VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer()
                if i.voice { Image(systemName: "waveform").font(.caption).foregroundStyle(.secondary) }
                Text(JarvisOutbox.shownText(i)).padding(10)
                    .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if i.state == .sending || (i.state == .queued && connected) { ProgressView().controlSize(.mini) }
                Text(status).font(.caption2).foregroundStyle(i.state == .failed ? Color.red : Color.secondary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("jarvisWaiting")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { if JarvisOutbox.actionable(i) { acting = i } }
    }

    /// „Jetzt senden“: sofort neu verbinden, der Sender der Outbox schickt die Nachricht, sobald die Verbindung steht.
    /// „Erneut senden“ nach einer Absage oder offenem Ausgang: wieder in die Warteschlange, unter neuer Kennung.
    private func sendNow(_ i: OutItem) {
        UsageRecorder.shared.record("jarvis", i.state == .failed ? "postausgang erneut" : "postausgang jetzt", kind: "text", length: i.text.count)
        if i.state == .failed { Outbox.shared.retry(i.id) }
        if model.state != .connected { model.reconnect() }
    }

    /// „Bearbeiten“: Text und Anhänge zurück in die Eingabe, die wartende Nachricht geht.
    private func editWaiting(_ i: OutItem) {
        let head = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = head.isEmpty ? i.text : head + "\n" + i.text
        var back: [JarvisDoc] = []
        if let dir = Outbox.filesDir {
            for f in i.files {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(f)) else { continue }
                let name = VaultChat.displayName(f)
                back.append(JarvisDoc(name: name, data: data, media: nil, preview: JarvisDocs.isPicture(name) ? AttachPrep.thumbnail(data) : nil))
            }
        }
        docs += back
        Outbox.shared.remove(i.id)
        UsageRecorder.shared.record("jarvis", "postausgang bearbeitet", kind: "text", length: i.text.count)
        inputFocused = true
    }

    private func deleteWaiting(_ i: OutItem) {
        UsageRecorder.shared.record("jarvis", "postausgang gelöscht", kind: "text", length: i.text.count)
        Outbox.shared.remove(i.id)
    }

    // MARK: Gesprächskontext

    /// Trennlinie im Verlauf: davor und danach sind es am PC zwei Gespräche.
    private func contextBreak(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jarvisBreak")
    }

    /// „Neues Gespräch beginnen“: Der PC beginnt für Jarvis ein neues Gespräch, der Verlauf auf dem iPhone bleibt.
    private func resetContext() async {
        do {
            try await model.jarvisReset()
            resets = JarvisContext.adding(Date().timeIntervalSince1970, to: resets)
            JarvisResets.save(resets)
            notice = JarvisContext.resetDone
            UsageRecorder.shared.record("jarvis", "neues gespräch")
            await loadContext()
        } catch { self.error = error.localizedDescription }
    }

    /// Füllstand des Gesprächs oder, wenn der Chief es führt, sein Name für „ablösen“.
    private func loadContext() async {
        let r = await model.jarvisInfo()
        context = r.flatMap(JarvisContext.status)
        lead = r.flatMap(JarvisContext.lead)
    }

    /// „Chief ablösen“: Das Gateway bittet den Chief, seine Notizen zu schreiben und sich abzulösen. Ersetzt wird die
    /// Sitzung am PC beim nächsten ruhigen Punkt, der Verlauf hier bleibt.
    private func handOver() async {
        do {
            let r = try await model.jarvisReset()
            notice = JarvisContext.handOverNotice(r, fallbackName: lead?.name ?? "")
            UsageRecorder.shared.record("jarvis", "chief ablösen")
            await loadContext()
        } catch { self.error = error.localizedDescription }
    }

    // MARK: voice

    /// While recording, the button ends the recording and keeps the words (into the field); while Jarvis answers or
    /// speaks, it stops everything; otherwise it starts listening.
    private func micTapped() {
        if voice.listening {
            endedBy = .stop
            UsageRecorder.shared.record("jarvis", "aufnahme gestoppt", kind: "diktat", length: voice.partial.count)
            voice.stopListening()
        } else if voiceTask != nil {
            stopVoice()
        } else {
            startVoice(trigger: "button")
        }
    }

    /// Send: typed text right away; during a recording the words heard so far go out together with the typed text.
    private func sendTapped() {
        if voice.listening {
            endedBy = .send
            voice.stopListening()
            return
        }
        let q = input; input = ""
        UsageRecorder.shared.content("jarvis", "gesendet", session: nil, kind: "text", text: q)
        Task { await submit(q, byVoice: false) }
    }

    private func startVoice(trigger: String) {
        guard voiceTask == nil else { return }
        voiceTask = Task {
            // nach dem Gespräch: wartende Rückmeldungen des Chiefs lesen, sonst das Audio freigeben
            defer { voiceTask = nil; model.conversationActive = false; if toSpeak.isEmpty { releaseIfDone() } else { speakPending() } }
            if let msg = await voice.authorize() { error = msg; return }
            var silent = 0
            var kind = trigger
            repeat {
                model.conversationActive = conversation
                let t0 = Date()
                let heard: String
                endedBy = .pause
                UsageRecorder.shared.record("jarvis", "diktat gestartet", kind: "diktat")
                SupertonicStore.shared.wake()  // Jarvis' Stimme lädt, während du sprichst
                do { heard = try await voice.listen() } catch {
                    UsageRecorder.shared.record("jarvis", "fehler", kind: "diktat", error: error.localizedDescription)
                    self.error = error.localizedDescription; return
                }
                if Task.isCancelled { return }
                // ohne Vorlesen braucht nach der Aufnahme niemand mehr das Audio: Musik läuft schon während der Antwort weiter
                if !speakAnswers { voice.releaseAudio() }
                let end = endedBy
                endedBy = .pause
                UsageRecorder.shared.content("jarvis", "diktiert", session: nil, kind: "diktat", text: heard)
                if end != .pause {
                    // stop button: the words go into the field; send button: typed and heard go out together
                    let o = JarvisDictation.outcome(heard: heard, end: end, typed: input)
                    input = o.field
                    if let q = o.ask {
                        await submit(q, byVoice: true, trigger: kind, t0: t0)
                        if speakAnswers { await voice.waitUntilSpoken() }
                    } else if end == .send, !docs.isEmpty {
                        // Senden ohne Worte, aber mit Dokumenten: Jarvis bekommt sie und fragt nach
                        await submit("", byVoice: false)
                    } else if !o.field.isEmpty {
                        inputFocused = true
                    }
                    return
                }
                if heard.isEmpty {
                    // a conversation ends after two silent turns in a row
                    silent += 1
                    if !conversation || silent >= 2 { return }
                    kind = "follow_up"
                    continue
                }
                silent = 0
                // "stop", "danke", "tschüss" end the conversation instead of being asked
                if conversation && SpeechText.isStopPhrase(heard) { return }
                let answered = await submit(heard, byVoice: true, trigger: kind, t0: t0)
                if speakAnswers { await voice.waitUntilSpoken() }
                // ohne Verbindung wartet die Frage in der Outbox: Das Gespräch endet hier, statt ins Leere zuzuhören
                if !answered { return }
                kind = "follow_up"
            } while conversation && !Task.isCancelled
        }
    }

    private func stopVoice() {
        voiceTask?.cancel()
        toSpeak = []
        voice.stopListening()
        voice.stopSpeaking()
        voiceTask = nil
        model.conversationActive = false
        voice.releaseAudio()
    }

    /// Gespräch und Vorlesen fertig: Audio an andere Apps zurück (Spotify spielt weiter). Nicht zwischen zwei Runden
    /// des Gesprächsmodus, dort läuft `voiceTask` noch.
    private func releaseIfDone() {
        guard voiceTask == nil, !voice.listening, !voice.speaking else { return }
        voice.releaseAudio()
    }

    private func loadVocab() async { await model.loadVocab(into: voice) }

    // MARK: Rückmeldungen des Chiefs

    /// Rückmeldungen, die im Speicher liegen und hier noch fehlen, ans Ende des Verlaufs; mit „Antworten vorlesen“
    /// liest die Stimme sie, das Thema zuerst.
    private func takeSays() {
        let new = JarvisSay.missing(in: turns.map(\.stored), stored: JarvisStore.load())
        guard !new.isEmpty else { return }
        turns += new.map(Turn.from)
        UsageRecorder.shared.record("jarvis", "rückmeldung", kind: "text", length: new.count)
        if speakAnswers {
            // Antworten auf Fragen aus der Warteschlange nur, wenn sie eingesprochen waren und die App vorn ist
            toSpeak += new.filter { JarvisOutbox.speaks($0, foreground: model.isForeground) }.map(JarvisSay.spoken)
            speakPending()
        }
    }

    /// Liest wartende Rückmeldungen, sobald die Stimme frei ist: nicht in eine laufende Antwort, nicht in eine Aufnahme
    /// und nicht mitten in ein Gespräch hinein (dort erst danach).
    private func speakPending() {
        guard !toSpeak.isEmpty, voiceTask == nil, !voice.speaking, !voice.listening else { return }
        let text = toSpeak.joined(separator: " ")
        toSpeak = []
        voice.speak(text)
    }

    /// Den Verlauf sichern. Rückmeldungen, die inzwischen im Speicher gelandet sind, bleiben dabei erhalten.
    private func persist() {
        JarvisStore.save(JarvisSay.merge(turns.map(\.stored), stored: JarvisStore.load()))
    }

    /// Ändert den Zug mit dieser Kennung. Mehrere Fragen können gleichzeitig offen sein, und „Chat löschen“ kann den
    /// Verlauf leeren, während eine Antwort noch aussteht: Dann geschieht nichts.
    private func edit(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[i])
    }

    // MARK: ask

    /// `shown`: was statt der Frage im Verlauf steht (Dokumente: Nachricht und Dateinamen statt des Auftrags mit Pfaden).
    /// `upload`: Die Frage ist ein Upload. Das Gateway macht daraus immer einen neuen Vorgang und nie die Antwort auf
    /// eine offene Rückfrage (`JarvisDocs.askParams`).
    /// Ohne Verbindung wartet die Frage in der Outbox und geht später von selbst hinaus (`queue`). Reißt die
    /// Verbindung beim Warten auf die Antwort, landet sie ebenfalls dort, statt als „Fehler“ zu enden.
    /// Ergebnis: true, wenn jetzt eine Antwort (oder eine Absage des Gateways) in der Zeile steht.
    @discardableResult
    private func ask(_ raw: String, byVoice: Bool, trigger: String? = nil, t0: Date? = nil, shown: String? = nil, upload: Bool = false) async -> Bool {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if model.state != .connected {
            queue(q, byVoice: byVoice, shown: shown, upload: upload)
            return false
        }
        // die Frage sperrt das Feld nicht: Während die Antwort aussteht, geht die nächste Nachricht sofort raus
        pending += 1; defer { pending -= 1 }
        notice = nil
        let turn = Turn(q: shown ?? q, a: "", done: false, voice: byVoice)
        let tid = turn.id
        turns.append(turn)
        let speak = byVoice && speakAnswers
        // Soll die Antwort vorgelesen werden, bleibt der Bildschirm an, bis sie da ist: Sperrt sich das iPhone beim
        // Warten, gibt iOS der App die Tonausgabe nicht mehr und die Antwort bliebe stumm.
        let awaiting = "jarvis-antwort-" + tid.uuidString
        if speak { ScreenAwake.shared.answerAwaited(awaiting) }
        defer { if speak { ScreenAwake.shared.answerArrived(awaiting) } }
        if speak {
            voice.keepsScreenOnWhileSpeaking = true  // auch während des Vorlesens, nicht nur beim Warten
            voice.beginReply()
        }
        // Eine Verbindung, die länger still war, kann tot sein (Flugmodus, PC schläft), auch wenn sie noch als
        // verbunden gilt: kurz prüfen. Ohne Antwort wartet die Frage in der Outbox, sie ging sicher nicht hinaus.
        if !(await model.ensureAlive()) {
            turns.removeAll { $0.id == tid }
            Outbox.shared.add(id: tid.uuidString, key: JarvisOutbox.key, text: q, voice: byVoice, shown: shown, upload: upload)
            UsageRecorder.shared.record("jarvis", "in postausgang", kind: byVoice ? "diktat" : "text", length: q.count)
            if speak { voice.speakUnlessStopped(JarvisOutbox.spokenQueued) }
            return false
        }
        let streamed = Flag()
        let stamp = Stamp()
        let sent = Date()
        do {
            // die Kennung der Zeile geht als `client_id` mit: Ein zweiter Versand derselben Frage löst nichts doppelt aus
            var params = JarvisDocs.askParams(text: q, byVoice: byVoice, upload: upload)
            params["client_id"] = .string(tid.uuidString)
            let r = try await model.rpc("ask", .object(params), timeout: 300, onProgress: { delta in
                Task { @MainActor in
                    edit(tid) { $0.a += delta }
                    if !streamed.value { stamp.first = Date() }
                    streamed.value = true
                    if speak { voice.feed(delta) }
                }
            }, onStatus: { o in
                // „Chief hat es“: Die Nachricht ist in seiner Sitzung, die Antwort kommt noch
                Task { @MainActor in
                    if let label = JarvisAsk.statusLabel(o) { edit(tid) { $0.status = label } }
                }
            })
            let final = r.str("text", turns.first(where: { $0.id == tid })?.a ?? "")
            if speak {
                await Task.yield()
                if streamed.value { voice.flush() } else { voice.speakUnlessStopped(final) }
            }
            edit(tid) { $0.a = final }
        } catch {
            let why = error.localizedDescription
            switch JarvisOutbox.outcome(remote: (error as? RelayError)?.remote ?? false, message: why, once: model.askOnce) {
            case .refused:
                edit(tid) { $0.a = "Fehler: \(why)" }
                if speak { voice.speakUnlessStopped("Das hat nicht geklappt.") }
            case .again:
                // nicht angekommen (oder das Gateway erkennt die Wiederholung): Die Frage wartet unter derselben Kennung
                turns.removeAll { $0.id == tid }
                Outbox.shared.add(id: tid.uuidString, key: JarvisOutbox.key, text: q, voice: byVoice, shown: shown, upload: upload)
                UsageRecorder.shared.record("jarvis", "in postausgang", kind: byVoice ? "diktat" : "text", length: q.count, error: why)
                if speak { voice.speakUnlessStopped(JarvisOutbox.spokenQueued) }
                return false
            case .unclear:
                // die Verbindung riss beim Warten: Ob die Frage am PC ist, weiß die App nicht. Sie bleibt stehen.
                turns.removeAll { $0.id == tid }
                Outbox.shared.addUnclear(id: tid.uuidString, text: q, voice: byVoice, shown: shown, upload: upload)
                UsageRecorder.shared.record("jarvis", "fehler", kind: byVoice ? "diktat" : "text", error: why)
                if speak { voice.speakUnlessStopped("Das hat nicht geklappt.") }
                return false
            }
        }
        edit(tid) { $0.done = true }
        persist()
        if let trigger, let t0, byVoice {
            func ms(_ d: Date) -> Int { Int(d.timeIntervalSince(t0) * 1000) }
            var stages = ["heard": ms(sent), "answer": ms(Date())]
            if let f = stamp.first { stages["first_text"] = ms(f) }
            model.sendVoiceTiming(trigger: trigger, stages: stages)
        }
        return true
    }
}

/// Rückmeldungen des Chiefs für den Jarvis-Chat (`jarvis_say`), wie sie das Modell aus dem Ereignisstrom bekommt: Sie
/// landen sofort im gespeicherten Verlauf, auch wenn der Chat nicht offen ist. `tick` sagt der offenen Ansicht, dass
/// etwas dazugekommen ist.
@MainActor
final class JarvisInbox: ObservableObject {
    static let shared = JarvisInbox()
    @Published var tick = 0
    /// Der Jarvis-Chat ist gerade zu sehen.
    var visible = false

    /// true, wenn die Rückmeldung neu ist (keine Wiederholung nach einer Verbindungspause).
    func receive(_ say: JarvisTurn) -> Bool {
        guard let all = JarvisSay.adding(say, to: JarvisStore.load()) else { return false }
        JarvisStore.save(all)
        tick += 1
        return true
    }
}

/// Scrollstand des Jarvis-Chats (`ChatScroll`) und die Höhe des sichtbaren Ausschnitts. Nur aus der Ansicht benutzt.
final class JarvisScrollBox {
    var scroll = ChatScroll()
    var viewport = 0.0
}

/// A mutable flag shared with progress callbacks (main actor only).
private final class Flag: @unchecked Sendable { var value = false }

private final class Stamp: @unchecked Sendable { var first: Date? }

/// Jarvis history on the device (Application Support, atomic), without events.
enum JarvisStore {
    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("jarvis-history.json")
    }
    static func load() -> [JarvisTurn] {
        guard let u = url, let d = try? Data(contentsOf: u) else { return [] }
        return JarvisHistory.decode(d)
    }
    static func save(_ turns: [JarvisTurn]) {
        guard let u = url, let d = JarvisHistory.encode(turns) else { return }
        try? d.write(to: u, options: .atomic)
    }
    static func clear() { if let u = url { try? FileManager.default.removeItem(at: u) } }
}

/// Wann auf diesem iPhone „Neues Gespräch beginnen“ getippt wurde (UserDefaults, höchstens 50 Zeitpunkte).
enum JarvisResets {
    private static let key = "jarvisResets"
    static func load() -> [Double] { (UserDefaults.standard.array(forKey: key) as? [Double]) ?? [] }
    static func save(_ list: [Double]) { UserDefaults.standard.set(list, forKey: key) }
}

/// "Erkennung korrigieren": teaches the Desktop a term, or what a misheard phrase meant.
struct TeachRecognitionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let voice: VoiceIO
    @State private var heard = ""
    @State private var meant = ""
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gehört (optional)", text: $heard).autocorrectionDisabled()
                    TextField("Gemeint", text: $meant).autocorrectionDisabled()
                } footer: {
                    Text("Nur „Gemeint“: ein neuer Begriff (Name, Fachwort). Mit „Gehört“: die falsch verstandene Wendung wird künftig ersetzt. Der Desktop merkt es sich in seiner Vokabelliste.")
                }
                if let e = error { Text(e).foregroundStyle(.red).font(.callout) }
                if let d = done { Text("Gemerkt: \(d)").foregroundStyle(.green).font(.callout) }
                Section("Bekannt (\(voice.corrections.count) \(voice.corrections.count == 1 ? "Korrektur" : "Korrekturen"), \(voice.terms.count) \(voice.terms.count == 1 ? "Begriff" : "Begriffe"))") {
                    ForEach(Array(voice.corrections.prefix(30).enumerated()), id: \.offset) { _, c in
                        Text("\(c.heard) → \(c.meant)").font(.callout)
                    }
                }
            }
            .navigationTitle("Erkennung korrigieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merken") { Task { await save() } }
                        .disabled(busy || meant.trimmingCharacters(in: .whitespaces).isEmpty || model.state != .connected)
                }
            }
        }
    }

    private func save() async {
        busy = true; error = nil; done = nil
        defer { busy = false }
        do {
            try await model.teachVocab(heard: heard, meant: meant, into: voice)
            done = meant; heard = ""; meant = ""
        } catch { self.error = error.localizedDescription }
    }
}
