import SwiftUI
import RelayCore

/// Jarvis, the overview agent on the Desktop (rpc `ask`, streamed). By voice: tap the microphone, speak, the answer is
/// read aloud sentence by sentence; in conversation mode it listens again after each answer until nothing is said.
struct JarvisView: View {
    @EnvironmentObject var model: AppModel
    var autoListen = false

    struct Turn: Identifiable { let id = UUID(); let q: String; var a: String; var done: Bool; let voice: Bool }
    @State private var turns: [Turn] = []
    @State private var input = ""
    @State private var asking = false
    @State private var error: String?
    @State private var voiceTask: Task<Void, Never>?
    @StateObject private var voice = VoiceIO()
    @AppStorage("jarvisSpeak") private var speakAnswers = true
    @AppStorage("jarvisConversation") private var conversation = true
    @AppStorage("jarvisLocale") private var locale = "de-DE"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if turns.isEmpty {
                            Text("Tippe aufs Mikrofon und sprich, z. B. „Was wartet auf mich?“ oder „Sag der Webapp-Sitzung, sie soll die Tests laufen lassen.“ Tipp: Mit dem Kurzbefehl „Jarvis in Relay“ geht das auch per Siri oder Aktionstaste.")
                                .font(.callout).foregroundStyle(.secondary).padding()
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
                    .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button { let q = input; input = ""; Task { await ask(q, byVoice: false) } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || asking)
            }.padding([.horizontal, .bottom])
        }
        .navigationTitle("Jarvis")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $speakAnswers) { Label("Antworten vorlesen", systemImage: "speaker.wave.2") }
                    Toggle(isOn: $conversation) { Label("Gesprächsmodus", systemImage: "bubble.left.and.bubble.right") }
                    Picker(selection: $locale) {
                        Text("Deutsch").tag("de-DE")
                        Text("English").tag("en-US")
                    } label: { Label("Sprache der Erkennung", systemImage: "globe") }
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .task {
            _ = try? await model.rpc("jarvis_warm")
            await loadVocab()
            if autoListen { startVoice() }
        }
        .onDisappear { stopVoice() }
    }

    private var micBar: some View {
        HStack(spacing: 16) {
            if voice.speaking {
                Button { voice.stopSpeaking() } label: { Label("Stopp", systemImage: "speaker.slash.fill") }.buttonStyle(.bordered)
            }
            Button { voice.listening || voiceTask != nil ? stopVoice() : startVoice() } label: {
                Image(systemName: voice.listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(voice.listening ? .red : Color.accentColor)
                    .symbolEffect(.pulse, isActive: voice.listening)
            }
            .disabled(asking && voiceTask == nil)
            .accessibilityLabel(voice.listening ? "Zuhören beenden" : "Sprechen")
        }
        .padding(.vertical, 6)
    }

    // MARK: voice

    private func startVoice() {
        guard voiceTask == nil else { return }
        voiceTask = Task {
            defer { voiceTask = nil }
            if let msg = await voice.authorize() { error = msg; return }
            repeat {
                let heard: String
                do { heard = try await voice.listen(locale: locale) } catch { self.error = error.localizedDescription; return }
                if heard.isEmpty || Task.isCancelled { return }
                await ask(heard, byVoice: true)
                if speakAnswers { await voice.waitUntilSpoken() }
            } while conversation && !Task.isCancelled
        }
    }

    private func stopVoice() {
        voiceTask?.cancel()
        voice.stopListening()
        voice.stopSpeaking()
        voiceTask = nil
    }

    private func loadVocab() async {
        guard let r = try? await model.rpc("voice_vocab", timeout: 10) else { return }
        voice.terms = r["terms"].array.compactMap(\.string)
        voice.corrections = r["corrections"].array.compactMap { (pair: JSON) -> (heard: String, meant: String)? in
            let a = pair.array
            guard a.count == 2, let h = a[0].string, let m = a[1].string else { return nil }
            return (h, m)
        }
    }

    // MARK: ask

    private func ask(_ raw: String, byVoice: Bool) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        asking = true; defer { asking = false }
        turns.append(Turn(q: q, a: "", done: false, voice: byVoice))
        let idx = turns.count - 1
        let speak = byVoice && speakAnswers
        let streamed = Flag()
        do {
            let r = try await model.rpc("ask", ["text": .string(q), "stream": true, "source": .string(byVoice ? "voice" : "text")], timeout: 300) { delta in
                Task { @MainActor in
                    turns[idx].a += delta
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
    }
}

/// A mutable flag shared with progress callbacks (main actor only).
private final class Flag: @unchecked Sendable { var value = false }
