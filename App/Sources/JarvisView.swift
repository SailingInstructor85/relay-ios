import SwiftUI
import RelayCore

/// Jarvis, the overview agent on the Desktop (rpc `ask`, streamed). By voice: tap the microphone, speak, the answer is
/// read aloud sentence by sentence; in conversation mode it listens again after each answer until nothing is said.
struct JarvisView: View {
    @EnvironmentObject var model: AppModel
    var autoListen = false

    struct Turn: Identifiable { var id = UUID(); let q: String; var a: String; var done: Bool; let voice: Bool; var ts = Date().timeIntervalSince1970 }
    @State private var turns: [Turn] = []
    @State private var input = ""
    @State private var asking = false
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.voiceLive {
                            Label("Der Desktop bietet Jarvis Live an. Das braucht den Sprachkanal des PCs und gibt es in dieser App nicht. Relay nutzt hier die Spracherkennung des iPhones.", systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        if turns.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(JarvisDictation.intro, systemImage: "info.circle").font(.callout)
                                    .accessibilityIdentifier("jarvisIntro")
                                Text(JarvisDictation.howTo).font(.callout).foregroundStyle(.secondary)
                            }.padding()
                        }
                        ForEach(turns) { t in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Spacer()
                                    if t.voice { Image(systemName: "waveform").font(.caption).foregroundStyle(.secondary) }
                                    Text(t.q).padding(10).background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                                }
                                if t.a.isEmpty && !t.done { ProgressView() } else { MarkdownText(text: t.a) }
                            }.padding(.horizontal).id(t.id)
                        }
                        if voice.listening {
                            HStack { Spacer(); Text(voice.partial.isEmpty ? "Ich höre…" : voice.partial).italic().foregroundStyle(.secondary).padding(10) }
                                .padding(.horizontal).id("partial")
                        }
                    }.padding(.vertical)
                }
                .onChange(of: turns.last?.a) { _, _ in if let id = turns.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                .onChange(of: voice.partial) { _, _ in proxy.scrollTo("partial", anchor: .bottom) }
            }
            if let e = error { ErrorBanner(text: Binding(get: { e }, set: { error = $0 })).padding(.vertical, 4) }
            micBar
            HStack {
                TextField("Jarvis schreiben…", text: $input, axis: .vertical).lineLimit(1...4)
                    .focused($inputFocused).accessibilityIdentifier("jarvisInput")
                    .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button { sendTapped() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }.disabled(!JarvisDictation.canSend(typed: input, listening: voice.listening, partial: voice.partial, asking: asking))
                    .accessibilityLabel("Senden").accessibilityIdentifier("jarvisSend")
            }.padding([.horizontal, .bottom])
        }
        .navigationTitle("Jarvis")
        .onAppear { UsageRecorder.shared.screen("jarvis") }
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
                    Button(role: .destructive) { confirmClear = true } label: { Label("Chat löschen", systemImage: "trash") }
                        .disabled(turns.isEmpty)
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .task {
            turns = JarvisStore.load().map { Turn(id: $0.id, q: $0.q, a: $0.a, done: true, voice: $0.voice, ts: $0.ts) }
            model.warmJarvis()
            await loadVocab()
            if autoListen { startVoice(trigger: "mic") }
        }
        .onChange(of: inputFocused) { _, focused in if focused { model.warmJarvis() } }
        .onDisappear { stopVoice() }
        .sheet(isPresented: $teaching) { TeachRecognitionView(voice: voice) }
        .confirmationDialog("Den Jarvis-Verlauf auf diesem iPhone löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Chat löschen", role: .destructive) { turns = []; JarvisStore.clear() }
        }
    }

    private var micBar: some View {
        HStack(spacing: 16) {
            if voice.speaking {
                Button { voice.stopSpeaking() } label: { Label("Stopp", systemImage: "speaker.slash.fill") }.buttonStyle(.bordered)
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
        Task { await ask(q, byVoice: false) }
    }

    private func startVoice(trigger: String) {
        guard voiceTask == nil else { return }
        voiceTask = Task {
            defer { voiceTask = nil; model.conversationActive = false }
            if let msg = await voice.authorize() { error = msg; return }
            var silent = 0
            var kind = trigger
            repeat {
                model.conversationActive = conversation
                let t0 = Date()
                let heard: String
                endedBy = .pause
                UsageRecorder.shared.record("jarvis", "diktat gestartet", kind: "diktat")
                do { heard = try await voice.listen() } catch {
                    UsageRecorder.shared.record("jarvis", "fehler", kind: "diktat", error: error.localizedDescription)
                    self.error = error.localizedDescription; return
                }
                if Task.isCancelled { return }
                let end = endedBy
                endedBy = .pause
                UsageRecorder.shared.content("jarvis", "diktiert", session: nil, kind: "diktat", text: heard)
                if end != .pause {
                    // stop button: the words go into the field; send button: typed and heard go out together
                    let o = JarvisDictation.outcome(heard: heard, end: end, typed: input)
                    input = o.field
                    if let q = o.ask {
                        await ask(q, byVoice: true, trigger: kind, t0: t0)
                        if speakAnswers { await voice.waitUntilSpoken() }
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
                await ask(heard, byVoice: true, trigger: kind, t0: t0)
                if speakAnswers { await voice.waitUntilSpoken() }
                kind = "follow_up"
            } while conversation && !Task.isCancelled
        }
    }

    private func stopVoice() {
        voiceTask?.cancel()
        voice.stopListening()
        voice.stopSpeaking()
        voiceTask = nil
        model.conversationActive = false
    }

    private func loadVocab() async { await model.loadVocab(into: voice) }

    // MARK: ask

    private func ask(_ raw: String, byVoice: Bool, trigger: String? = nil, t0: Date? = nil) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        asking = true; defer { asking = false }
        turns.append(Turn(q: q, a: "", done: false, voice: byVoice))
        let idx = turns.count - 1
        let speak = byVoice && speakAnswers
        let streamed = Flag()
        let stamp = Stamp()
        let sent = Date()
        do {
            let r = try await model.rpc("ask", ["text": .string(q), "stream": true, "source": .string(byVoice ? "voice" : "text")], timeout: 300) { delta in
                Task { @MainActor in
                    turns[idx].a += delta
                    if !streamed.value { stamp.first = Date() }
                    streamed.value = true
                    if speak { voice.feed(delta) }
                }
            }
            let final = r.str("text", turns[idx].a)
            if speak {
                await Task.yield()
                if streamed.value { voice.flush() } else { voice.speak(final) }
            }
            turns[idx].a = final
        } catch {
            turns[idx].a = "Fehler: \(error.localizedDescription)"
            if speak { voice.speak("Das hat nicht geklappt.") }
        }
        turns[idx].done = true
        JarvisStore.save(turns.map { JarvisTurn(id: $0.id, q: $0.q, a: $0.a, voice: $0.voice, ts: $0.ts) })
        if let trigger, let t0, byVoice {
            func ms(_ d: Date) -> Int { Int(d.timeIntervalSince(t0) * 1000) }
            var stages = ["heard": ms(sent), "answer": ms(Date())]
            if let f = stamp.first { stages["first_text"] = ms(f) }
            model.sendVoiceTiming(trigger: trigger, stages: stages)
        }
    }
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
