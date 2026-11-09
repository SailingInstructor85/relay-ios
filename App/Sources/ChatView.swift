import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import RelayCore

/// One session as a chat: its transcript, the live menu card (questions, pickers, permission prompts) and an input bar
/// whose text goes into the real TUI through tmux.
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    let sessionKey: String
    /// From the app-wide search: opens the chat's own search with this query.
    var initialSearch: String? = nil

    @State private var messages: [TMessage] = []
    @State private var before: String?
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var input = ""
    @State private var sending = false
    @State private var menu: ScreenMenu?
    @State private var runItems: [RunningItem] = []
    @State private var live: LiveStatus?
    @State private var preview = ""
    @State private var runningOpen = false
    @State private var chatCtx = ChatContext()
    @State private var summary: SummaryState?
    @State private var camera = false
    @State private var dictating = false
    @State private var sendAfterDictation = false
    @State private var vocabLoaded = false
    /// Diktierter Text steht im Feld und ist noch nicht gesendet: andere Apps (Spotify) bleiben pausiert.
    @State private var dictated = false
    @StateObject private var voice = VoiceIO()
    /// Vorlesen auf Knopfdruck: eine Antwort, die letzte Antwort oder nur die Frage (ReadAloud), mit Pause und Stopp.
    @ObservedObject private var reader = SpeechOut.shared
    @ObservedObject private var outbox = Outbox.shared
    @State private var error: String?
    @State private var confirmForce: String?
    /// Postausgang-Kennung der Nachricht, für die Martin im Postausgang „Am PC beenden und hier fortsetzen…“ getippt hat;
    /// die Bestätigung folgt (DeskTerminal). Seit 0.3.7 nicht mehr von selbst nach einer Absage.
    @State private var confirmMove: String?
    @State private var importing = false
    @State private var pickingPhoto = false
    @State private var uploadInfo = ""
    @State private var showScreen = false
    @State private var showSearch = false
    @State private var initialDone = false
    @AppStorage("returnSends") private var returnSends = false
    @State private var standTick = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var highlight: String?
    @State private var jumpTo: String?
    @State private var viewer: RemoteRef?
    @State private var menuMessage: TMessage?
    @FocusState private var focused: Bool
    /// Lesemodus: Navigationsleiste, Eingabezeile und Tastatur weg, der Verlauf füllt den Bildschirm (ReadingMode).
    @State private var reading = false

    private var session: Session? { model.session(for: sessionKey) }
    private var key: String { session?.key ?? sessionKey }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if before != nil {
                            Button(loading ? "Lade…" : "Ältere Nachrichten laden") { Task { await loadOlder() } }
                                .font(.footnote).frame(maxWidth: .infinity).padding(.top, 8)
                        } else if loadedOnce && !messages.isEmpty {
                            Text("Anfang des Gesprächs").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
                        }
                        ForEach(messages) { m in MessageRow(m: m, highlighted: m.id == highlight).id(m.id) }
                        ForEach(outbox.items(for: key)) { item in
                            OutboxRow(item: item, onEdit: { text in input = text; focused = true }, onMove: { confirmMove = $0 })
                        }
                        if let s = session, s.state == "busy" || !runItems.isEmpty { workingLine(s) }
                        if let s = session, s.asksYou, !s.asksText.isEmpty {
                            AsksCard(text: s.asksText, speak: { reader.speak($0) }) { Task { await model.done(s) } }
                        }
                        if let s = session { cards(s) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                // ein Tipp in den Verlauf schließt die Tastatur; Text und laufendes Diktat bleiben (nur der Fokus geht)
                .simultaneousGesture(TapGesture().onEnded { if focused { focused = false } })
                .environment(\.chatActions, ChatActions(
                    openPath: { p in openPath(p) },
                    openFile: { viewer = $0 },
                    menu: { menuMessage = $0 },
                    speak: { reader.speak($0) }))
                .environment(\.openURL, OpenURLAction { url in
                    MainActor.assumeIsolated {
                        LinkRouter.open(url.absoluteString, base: session?.cwd, onFile: { viewer = $0 }, onError: { error = $0 })
                    }
                    return .handled
                })
                .onChange(of: messages.count) { _, _ in
                    outbox.sweep(seen: messages.filter { $0.role == "user" }.map(\.text))
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: outbox.items.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: menu?.id) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: jumpTo) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .top) }; jumpTo = nil }
                }
            }
            if let sm = summary {
                SummaryCard(state: sm, speaking: voice.speaking, onSpeak: { voice.speak($0) }, onStop: { voice.stopSpeaking() },
                            onClose: { voice.stopSpeaking(); summary = nil })
            }
            if reader.speaking { ReadAloudBar(reader: reader) }
            if let e = error { ErrorBanner(text: Binding(get: { e }, set: { error = $0 })).padding(.vertical, 4) }
            if !uploadInfo.isEmpty { Text(uploadInfo).font(.caption).foregroundStyle(.secondary).padding(.top, 4) }
            if ReadingMode.chrome(reading: reading).inputBar { inputBar }
        }
        .navigationTitle(session?.name ?? "Sitzung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .toolbar(ReadingMode.chrome(reading: reading).navigationBar ? .visible : .hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) { if reading { readingExit } }
        .onChange(of: session?.state) { old, new in
            if old == "busy" && new != "busy" { Task { await loadContext() } }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                camera = false
                if let img, let d = img.jpegData(compressionQuality: 0.95) {
                    Task { await upload(name: "kamera-\(Int(Date().timeIntervalSince1970)).jpg", data: d, photo: true) }
                }
            }.ignoresSafeArea()
        }
        .sheet(isPresented: $showSearch) {
            ChatSearchView(sessionKey: key, initial: initialSearch ?? "") { id, index in Task { await jump(to: id, index: index) } }.environmentObject(model)
        }
        .sheet(item: $viewer) { r in
            FileViewerView(start: r, base: session?.cwd).environmentObject(model)
        }
        .sheet(item: $menuMessage) { m in
            MessageMenu(message: m, base: session?.cwd, onFile: { viewer = $0 }).environmentObject(model)
        }
        .sheet(isPresented: $showScreen) {
            if let s = session { NavigationStack { ScreenView(session: s) }.environmentObject(model) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await uploadFile(url) } }
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoLibraryPicker { provider in
                pickingPhoto = false
                if let provider { Task { await uploadPicked(provider) } }
            }.ignoresSafeArea()
        }
        .confirmationDialog(DeskTerminal.dialogTitle, isPresented: Binding(get: { confirmMove != nil }, set: { if !$0 { confirmMove = nil } }), titleVisibility: .visible) {
            Button(DeskTerminal.moveConfirm, role: .destructive) { if let id = confirmMove { Outbox.shared.retry(id, move: true) } }
        } message: { Text(DeskTerminal.dialogMessage) }
        .confirmationDialog("Die Sitzung arbeitet gerade.", isPresented: Binding(get: { confirmForce != nil }, set: { if !$0 { confirmForce = nil } }), titleVisibility: .visible) {
            Button("Trotzdem senden") { if let id = confirmForce { Outbox.shared.retry(id, force: true) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Nachricht wartet im Chat, bis du sie trotzdem sendest, bearbeitest oder verwirfst.")
        }
        .task(id: key) { await openChat() }
        .onAppear {
            model.rememberOpened(key)
            UsageRecorder.shared.screen("chat", session: key)
            if let q = initialSearch, !q.isEmpty, !initialDone { initialDone = true; showSearch = true }
        }
        .onChange(of: scenePhase) { _, p in if p == .active { standTick += 1 } }
        .onChange(of: error) { _, e in if let e { UsageRecorder.shared.record("chat", "fehler", session: key, error: e) } }
        .onChange(of: focused) { _, f in UsageRecorder.shared.record("chat", f ? "tastatur auf" : "tastatur zu", session: key, length: input.count) }
        .keepsScreenAwake()
        // Nachricht fertig (gesendet, in den Postausgang, Feld geleert): Musik anderer Apps läuft weiter
        .onChange(of: input) { _, t in
            guard t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !voice.listening, !dictating else { return }
            dictated = false
            voice.releaseAudio()
        }
        .onChange(of: voice.speaking) { _, s in
            if !s, !voice.listening, !dictating, !dictated { voice.releaseAudio() }
        }
        .onDisappear {
            model.visibleChat = nil
            model.transcriptListeners[sessionKey] = nil
            voice.stopSpeaking(); voice.stopListening(); reader.stop()
            dictated = false
            voice.releaseAudio()
            Task { _ = try? await model.rpc("unwatch", ["key": .string(key)]) }
        }
    }

    // MARK: input

    private var tool: String { session?.tool ?? "claude" }
    private var slashChips: [String] { ChatPrefs.slash(tool) }
    private var slashSuggestions: [String] { SlashCatalog.matches(SlashCatalog.forTool(tool, user: slashChips), input) }
    private var canSend: Bool {
        DictationSend.canSend(input: input, listening: voice.listening, sending: sending, hasSession: session != nil)
    }

    /// Sitzung am PC in einem Terminal ohne tmux: Hinweis, keine Sperre. Nachrichten gehen in den Postausgang; der Umzug
    /// in tmux nur über den Knopf dort und eine Bestätigung (Martin, 2026-11-07: nie ungefragt am PC beenden).
    private var deskHint: some View {
        HStack(spacing: 8) {
            Image(systemName: PCPresence.symbol).foregroundStyle(.secondary)
            Text(DeskTerminal.hint).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal).padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deskHint")
    }

    /// Knopf „Tastatur ausblenden“: am rechten Ende der Schnellantwort-Zeile statt in der Leiste über der Tastatur, wo
    /// er Senden und Mikrofon teilweise verdeckte (Martin, 2026-11-07). Tippfläche mindestens 44 pt.
    private var hideKeyboardButton: some View {
        Button { focused = false } label: {
            Image(systemName: "keyboard.chevron.compact.down").font(.body)
                .frame(minWidth: KeyboardBar.minTapSize, minHeight: KeyboardBar.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        .accessibilityLabel(KeyboardBar.hideLabel).accessibilityIdentifier("hideKeyboard")
    }

    /// Schnellantworten und rechts daneben der Tastatur-Knopf; ohne Schnellantworten nur der Knopf in einer schmalen Zeile.
    @ViewBuilder private func quickRow(_ quick: [String]) -> some View {
        let row = KeyboardBar.row(quickCount: quick.count, keyboardOpen: focused, slashSuggestions: !slashSuggestions.isEmpty)
        if row.visible {
            HStack(spacing: 4) {
                if row.quickReplies {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quick, id: \.self) { q in
                                Button(q) { Task { await send(q) } }.font(.callout)
                                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
                                    .disabled(session == nil)
                            }
                        }.padding(.horizontal)
                    }
                } else {
                    Spacer(minLength: 0)
                }
                if row.hideButton { hideKeyboardButton.padding(.trailing, 8) }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let s = session, DeskTerminal.isDeskTerminal(s) { deskHint }
            if !slashSuggestions.isEmpty {
                quickRow([])
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(slashSuggestions, id: \.self) { c in
                            Button { input = c + " "; focused = true } label: {
                                Text(c).font(.system(.callout, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }.padding(.horizontal)
                }.frame(maxHeight: 190)
            } else {
                quickRow(ChatPrefs.quickReplies)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(slashChips, id: \.self) { c in
                            Button(c) { input = c + " "; focused = true }.font(.caption).buttonStyle(.bordered).buttonBorderShape(.capsule)
                        }
                        Button { Task { if let s = session { try? await model.sendKeys(s, ["Escape"]); await refreshScreen() } } } label: { Text("Esc") }
                            .font(.caption).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.red)
                    }.padding(.horizontal)
                }
            }
            if voice.listening {
                Label(voice.partial.isEmpty ? "Höre zu…" : voice.partial, systemImage: "waveform").font(.footnote)
                    .foregroundStyle(.red).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    // A picker inside a Menu does not open on iOS; the menu item sets a flag for the sheet below, a moment
                    // later so the menu has closed first (presenting while it closes was dropped on the iPhone).
                    Button { Task { try? await Task.sleep(nanoseconds: 350_000_000); pickingPhoto = true } } label: { Label("Foto oder Video", systemImage: "photo") }
                    if CameraPicker.available { Button { camera = true } label: { Label("Kamera", systemImage: "camera") } }
                    if UIPasteboard.general.hasImages { Button { Task { await uploadClipboard() } } label: { Label("Bild aus Zwischenablage", systemImage: "doc.on.clipboard") } }
                    Button { importing = true } label: { Label("Datei", systemImage: "doc") }
                } label: { Image(systemName: "paperclip").font(.title3) }.accessibilityLabel("Anhängen").accessibilityIdentifier("attach")
                TextField("Nachricht an die Sitzung", text: $input, axis: .vertical)
                    .lineLimit(1...6).focused($focused).accessibilityIdentifier("chatInput")
                    .submitLabel(returnSends ? .send : .return)
                    .onSubmit { if returnSends && canSend { Task { await sendTapped() } } }
                    .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button { Task { await toggleDictation() } } label: {
                    Image(systemName: voice.listening ? "mic.fill" : "mic").font(.title3).foregroundStyle(voice.listening ? Color.red : Color.accentColor)
                }.accessibilityLabel(voice.listening ? "Diktat beenden" : "Diktieren").accessibilityIdentifier("chatMic")
                Button { Task { await sendTapped() } } label: {
                    Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill").font(.system(size: 30))
                }.disabled(!canSend).accessibilityLabel("Senden").accessibilityIdentifier("chatSend")
            }
            .padding(.horizontal).padding(.bottom, 6)
        }
        .padding(.top, 6)
        .background(.bar)
    }

    // MARK: header, working line, cards

    private var headerSubtitle: String {
        guard let s = session else { return "" }
        let tokens = chatCtx.tokens > 0 ? chatCtx.tokens : s.context?.tokens
        let model = chatCtx.model.isEmpty ? (s.context?.model ?? "") : chatCtx.model
        return ChatHeader.subtitle(model: model, effort: chatCtx.effort, tool: s.tool, cwd: s.cwd, tokens: tokens)
    }

    @ViewBuilder private var titleView: some View {
        let label = VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(session?.name ?? "Sitzung").font(.headline).lineLimit(1)
                if let s = session, PCPresence.of(s) == .open {  // auch am PC offen (nur Anzeige, keine Sperre)
                    Image(systemName: PCPresence.symbol).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(PCPresence.openLabel).accessibilityIdentifier("pcOpen")
                }
            }
            Text(headerSubtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            if let la = session?.lastActivity, la > 0 {
                // the clock is read anew on every pass and when the app comes back (a timer alone sleeps with the phone)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(StandText.text(lastActivity: la, now: Date())).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }.id(standTick)
            }
        }
        .frame(maxWidth: 190) // die Symbolleiste rechts ist breit; ohne Grenze quillt der Untertitel unter die Knöpfe
        if session?.tool == "claude" {
            Menu {
                let idle = session?.state != "busy"
                Section("Modell") {
                    ForEach(ChatHeader.models, id: \.self) { m in
                        Button { Task { await switchTo("/model \(m)") } } label: {
                            if chatCtx.model.contains(m) { Label(m, systemImage: "checkmark") } else { Text(m) }
                        }.disabled(!idle)
                    }
                }
                Section("Effort") {
                    ForEach(ChatHeader.efforts, id: \.self) { l in
                        Button { Task { await switchTo("/effort \(l)") } } label: {
                            if chatCtx.effort == l { Label(l, systemImage: "checkmark") } else { Text(l) }
                        }.disabled(!idle)
                    }
                }
                if !idle { Text("Wechsel, wenn die Sitzung idle ist") }
            } label: { label.foregroundStyle(.primary) }
        } else {
            label
        }
    }

    private func switchTo(_ cmd: String) async {
        guard let s = session else { return }
        do { try await model.send(s, text: cmd); error = nil } catch { self.error = "Nicht umgestellt: \(error.localizedDescription)" }
    }

    @ViewBuilder private func workingLine(_ s: Session) -> some View {
        let busy = s.state == "busy"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if busy { ProgressView() }
                VStack(alignment: .leading, spacing: 2) {
                    if busy {
                        let info = RunningText.info(live)
                        Text(((live?.verb ?? "arbeitet") + "… " + info).trimmingCharacters(in: .whitespaces)).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !runItems.isEmpty {
                        Button { withAnimation { runningOpen.toggle() } } label: {
                            HStack(spacing: 4) {
                                Text(RunningText.summary(runItems)).font(.caption)
                                Image(systemName: runningOpen ? "chevron.up" : "chevron.down").font(.caption2)
                            }
                        }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                if busy {
                    Button { Task { await stop(s) } } label: { Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red) }
                        .accessibilityLabel("Stoppen")
                }
            }
            if runningOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(runItems) { r in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: RunningText.icon(r.kind)).font(.caption).foregroundStyle(.secondary).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.label).font(.caption).lineLimit(2)
                                Text(([RunningText.what(r), RunningText.elapsed(since: r.since, now: Date().timeIntervalSince1970)]
                                      + (r.activity.isEmpty ? [] : [r.activity])).filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            if busy && !preview.isEmpty {
                Text(preview).font(.footnote).foregroundStyle(.secondary).lineLimit(6)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal)
    }

    private func stop(_ s: Session) async {
        UsageRecorder.shared.record("chat", "gestoppt", session: s.key)
        do { try await model.stopTurn(s); error = nil; await refreshRunning() } catch { self.error = "Nicht gestoppt: \(error.localizedDescription)" }
    }

    /// The card at the bottom: the agent's question as a form while it waits, else the menu the TUI shows (a permission
    /// prompt, a picker). A form that can't be answered by keys falls back to the screen's own menu.
    @ViewBuilder private func cards(_ s: Session) -> some View {
        if let q = s.question, menu == nil || menu?.kind == "question" {
            if AnswerKeys.usable(q) || AnswerKeys.formUsable(q) {
                QuestionFormCard(q: q, session: s) { await refreshScreen() }.id("\(q.text)#\(q.count)")
            } else if let m = menu {
                MenuCard(menu: m, session: s) { await refreshScreen() }
            } else {
                QuestionCard(q: q, speak: { reader.speak($0) })
            }
        } else if let m = menu {
            MenuCard(menu: m, session: s) { await refreshScreen() }
        }
    }

    /// Was „Frage vorlesen“ sagt: die offene Frage der Sitzung (Karte) mit Optionen, sonst ihr Wartetext, sonst die Frage
    /// in der letzten Antwort (ReadAloud.question). Nil, wenn nichts gefragt ist.
    private var spokenQuestion: String? {
        if let q = session?.question { return ReadAloud.spoken(question: q) }
        if let s = session, s.asksYou, !s.asksText.isEmpty { return ReadAloud.cleaned(s.asksText) }
        return ReadAloud.lastAnswer(messages).flatMap { ReadAloud.question(in: $0.text) }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) { titleView }
        ToolbarItem(placement: .topBarTrailing) {
            let queue = Triage.queue(model.triageSessions, unread: model.unread, current: key)
            HStack(spacing: 8) {
                if let s = session { StateBadge(state: s.shownState) }
                if let next = queue.first {
                    Button { model.openChat = next.key } label: { Label("Weiter (\(queue.count))", systemImage: "forward.end").font(.footnote.weight(.semibold)) }
                        .accessibilityLabel("Weiter zur nächsten Sitzung, \(queue.count) offen")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let s = session {
                    if s.liveTmux != nil { Button { showScreen = true } label: { Label("Live-Bildschirm", systemImage: "terminal") } }
                    Button { showSearch = true } label: { Label("Im Verlauf suchen", systemImage: "magnifyingglass") }
                    Button { Task { await summarize() } } label: { Label("Zusammenfassen", systemImage: "text.alignleft") }
                        .disabled(summary?.loading == true)
                    if let last = ReadAloud.lastAnswer(messages) {
                        Button { reader.speak(last.text) } label: { Label("Letzte Antwort vorlesen", systemImage: "speaker.wave.2") }
                    }
                    if let q = spokenQuestion {
                        Button { reader.speak(q) } label: { Label("Frage vorlesen", systemImage: "questionmark.bubble") }
                    }
                    if reader.speaking {
                        Button { reader.stop() } label: { Label("Vorlesen beenden", systemImage: "speaker.slash") }
                    }
                    if s.state == "busy" { Button { Task { await stop(s) } } label: { Label("Stoppen", systemImage: "stop.circle") } }
                    Button { model.togglePin(s.key) } label: { Label(model.pinned.contains(s.key) ? "Loslösen" : "Anheften", systemImage: "pin") }
                    Button { model.toggleMute(s.key) } label: {
                        Label(model.muted.contains(s.key) ? "Mitteilungen an" : "Stummschalten", systemImage: model.muted.contains(s.key) ? "bell" : "bell.slash")
                    }
                    if s.waits { Button { Task { await model.done(s) } } label: { Label("Als erledigt markieren", systemImage: "checkmark") } }
                    if s.exited || s.closed || s.hibernated {
                        Button { Task { do { _ = try await model.reopen(s); await model.refresh() } catch { self.error = error.localizedDescription } } } label: { Label("Wieder öffnen", systemImage: "arrow.uturn.backward") }
                    } else if s.alive {
                        Button(role: .destructive) { Task { await model.close(s) } } label: { Label("Sitzung schließen", systemImage: "xmark.circle") }
                    }
                    if !s.remoteUrl.isEmpty, let u = URL(string: s.remoteUrl) { Link(destination: u) { Label("In Claude öffnen", systemImage: "safari") } }
                    Section("\(s.alias) · \(s.tool)") {
                        Text(s.cwd)
                        if let c = s.context { Text("Kontext: \(c.label) (\(c.pct) %)") }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Sitzungsmenü").accessibilityIdentifier("chatMenu")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if session?.liveTmux != nil { Button { showScreen = true } label: { Image(systemName: "terminal") } }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { toggleReading() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .accessibilityLabel(ReadingMode.enterLabel).accessibilityIdentifier("readingOn")
        }
    }

    // MARK: Lesemodus

    /// Nur der Verlauf, ohne Leisten; die Tastatur geht zu, der Text im Feld bleibt. Neue Nachrichten laufen weiter ein
    /// (der Verlauf ist derselbe), der Bildschirm bleibt wie beim Zuschauen an (`keepsScreenAwake` gilt für den ganzen Chat).
    private func toggleReading() {
        let t = ReadingMode.toggle(reading: reading)
        if t.closesKeyboard { focused = false }
        withAnimation { reading = t.reading }
    }

    /// Der kleine Knopf oben rechts, der die normale Ansicht zurückbringt.
    private var readingExit: some View {
        Button { toggleReading() } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left").font(.body.weight(.semibold))
                .padding(10).background(.regularMaterial, in: Circle())
        }
        .padding(.trailing, 12).padding(.top, 6)
        .accessibilityLabel(ReadingMode.exitLabel).accessibilityIdentifier("readingOff")
    }

    private func openPath(_ path: String) {
        Task {
            do { viewer = try await FileStore.shared.info(path) }
            catch { self.error = error.localizedDescription }
        }
    }

    // MARK: loading

    private func openChat() async {
        model.visibleChat = key
        model.markRead(key)
        model.transcriptListeners[sessionKey] = { k, msgs in
            guard k == key || session?.matches(k) == true else { return }
            let known = Set(messages.map(\.id))
            messages.append(contentsOf: msgs.filter { !known.contains($0.id) })
        }
        // wait for the link if it is just coming up
        for _ in 0..<40 where model.state != .connected { try? await Task.sleep(nanoseconds: 250_000_000) }
        if !loadedOnce { await loadLatest() }
        _ = try? await model.rpc("watch", ["key": .string(key)])
        // poll the menu and the running status while the chat is open
        var tick = 0
        while !Task.isCancelled {
            if let s = session {
                if s.liveTmux != nil && (s.state != "busy" || tick % 2 == 0) { await refreshScreen() }
                if s.state == "busy" || !runItems.isEmpty || tick % 10 == 0 { await refreshRunning() }
                if s.state != "busy" { live = nil; preview = "" }
            }
            tick += 1
            try? await Task.sleep(nanoseconds: (session?.state == "busy" ? 1_500_000_000 : 2_500_000_000))
        }
    }

    private func loadLatest() async {
        loading = true; defer { loading = false }
        do {
            let r = try await model.rpc("transcript", ["key": .string(key), "limit": 50])
            messages = r["messages"].array.map(TMessage.from)
            before = r["before"].string
            loadedOnce = true
            applyContext(r["context"])
        } catch { self.error = error.localizedDescription }
    }

    private func loadOlder() async {
        guard let b = before, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let r = try await model.rpc("transcript", ["key": .string(key), "limit": 50, "before": .string(b)])
            let older = r["messages"].array.map(TMessage.from)
            let known = Set(messages.map(\.id))
            messages.insert(contentsOf: older.filter { !known.contains($0.id) }, at: 0)
            before = r["before"].string
        } catch { self.error = error.localizedDescription }
    }

    /// Shows a search hit: loads the transcript from its index when it isn't loaded yet, scrolls there, highlights it.
    private func jump(to id: String, index: Int) async {
        if !messages.contains(where: { $0.id == id }) {
            loading = true; defer { loading = false }
            do {
                let r = try await model.rpc("transcript", ["key": .string(key), "from": .number(Double(index))], timeout: 30)
                messages = r["messages"].array.map(TMessage.from)
                before = r["before"].string
            } catch { self.error = error.localizedDescription; return }
        }
        try? await Task.sleep(nanoseconds: 350_000_000) // let the list lay out first
        highlight = id
        jumpTo = id
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if highlight == id { withAnimation { highlight = nil } }
    }

    private func refreshScreen() async {
        guard let s = session, s.liveTmux != nil else { menu = nil; return }
        if let r = try? await model.rpc("screen", ["target": .string(s.target), "lines": 60, "escapes": false, "menu": true], timeout: 10) {
            let m = ScreenMenu.from(r["menu"])
            if m?.id != menu?.id || (m == nil) != (menu == nil) { menu = m }
        }
    }

    private func refreshRunning() async {
        guard let r = try? await model.rpc("running", ["key": .string(key)], timeout: 8) else { return }
        let items = RunningItem.list(from: r)
        if items != runItems { runItems = items }
        live = LiveStatus.from(r)
        let raw = r.has("preview") ? r.str("preview") : r["status"].str("preview")
        let last = messages.last { $0.role == "assistant" }?.text ?? ""
        preview = RunningText.freshPreview(raw, lastReply: last)
    }

    private func applyContext(_ c: JSON) {
        guard c.object != nil else { return }
        chatCtx = ChatContext(model: c.str("model"), effort: c.str("effort"), tokens: c["tokens"].int ?? 0)
    }

    /// Model, effort and context size of the newest request (the `transcript` result's `context`).
    private func loadContext() async {
        if let r = try? await model.rpc("transcript", ["key": .string(key), "limit": 1], timeout: 15) { applyContext(r["context"]) }
    }

    private func summarize() async {
        guard let s = session else { return }
        summary = SummaryState(loading: true)
        do { summary = SummaryState(text: try await model.summarize(s)) }
        catch { summary = SummaryState(error: error.localizedDescription) }
    }

    /// Sends at once when the link is up (a quiet one is pinged first); otherwise, or when the link fails meanwhile, the
    /// message goes into the outbox, which sends it as soon as the Desktop answers (same `client_id`, so never twice).
    /// A message is never dropped without a word: a refusal because the session works keeps it in the outbox (grey
    /// bubble with "Trotzdem senden", "Bearbeiten", "Verwerfen"), any other refusal leaves it in the field with a banner.
    private func send(_ text: String, force: Bool = false) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard let s = session else { error = "Nicht gesendet: die Sitzung ist nicht mehr in der Liste."; return }
        let id = UUID().uuidString
        func clearField() { if input.trimmingCharacters(in: .whitespacesAndNewlines) == t { input = "" } }
        func queue() {
            UsageRecorder.shared.content("chat", "in postausgang", session: s.key, kind: "text", text: t)
            Outbox.shared.add(id: id, key: s.key, text: t, force: force)
            clearField()
            error = nil
        }
        guard model.state == .connected else { queue(); return }
        sending = true; defer { sending = false }
        guard await model.ensureAlive() else { queue(); return }
        do {
            try await model.send(s, text: t, force: force, clientId: id)
            UsageRecorder.shared.content("chat", "gesendet", session: s.key, kind: "text", text: t)
            clearField()
            error = nil
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshScreen()
        } catch let e as RelayError where e.remote && OutboxLogic.isBusyRefusal(e.message) {
            Outbox.shared.addRefused(id: id, key: s.key, text: t, error: e.message)
            UsageRecorder.shared.content("chat", "abgelehnt (arbeitet)", session: s.key, kind: "text", text: t)
            clearField()
            error = nil
            confirmForce = id
        } catch let e as RelayError where e.remote && DeskTerminal.isRefusal(e.message) {
            // at the PC in a terminal outside tmux: the text waits in the outbox (grey bubble with the reason); the move
            // into tmux only from the button there and after his yes, never offered by itself (Martin, 2026-11-07)
            Outbox.shared.addRefused(id: id, key: s.key, text: t, error: e.message)
            UsageRecorder.shared.content("chat", "abgelehnt (PC ohne tmux)", session: s.key, kind: "text", text: t)
            clearField()
            error = nil
        } catch let e as RelayError where e.remote && SubmitCheck.isStuck(e.message) {
            // typed at the PC but not submitted (Enter lost twice): sending again would type it twice
            UsageRecorder.shared.content("chat", "nicht abgeschickt (eingabefeld)", session: s.key, kind: "text", text: t)
            clearField()
            error = SubmitCheck.text
        } catch {
            if OutboxLogic.retries(error) { queue() } else { self.error = error.localizedDescription }
        }
    }

    // MARK: dictation

    private func join(_ before: String, _ said: String) -> String {
        before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n") ? before + said : before + " " + said
    }

    /// The send button. While dictating, the microphone stays on for `DictationSend.grace` so the last words are still
    /// recognised; then the dictation ends and `toggleDictation` sends typed and spoken text together. Should the words
    /// not arrive within `DictationSend.stuckAfter` (a recogniser or clean-up that never answers), the button is freed
    /// with what is in the field, so the chat never stays blocked.
    private func sendTapped() async {
        guard voice.listening else { await send(input); return }
        guard !sendAfterDictation else { return }
        sendAfterDictation = true
        sending = true
        try? await Task.sleep(nanoseconds: UInt64(DictationSend.grace * 1_000_000_000))
        voice.stopListening()
        let until = Date().addingTimeInterval(DictationSend.stuckAfter)
        while sendAfterDictation && Date() < until { try? await Task.sleep(nanoseconds: 250_000_000) }
        if sendAfterDictation {
            UsageRecorder.shared.record("chat", "diktat hängt", session: key, kind: "diktat")
            sendAfterDictation = false
            sending = false
            dictating = false
            error = "Das Diktat hat nicht geantwortet. Der Text steht im Feld, bitte noch einmal auf Senden tippen."
        }
    }

    /// Mic button: listens until the speaker pauses (or the button is tapped again), then puts the words into the field.
    /// With "Diktat aufräumen" the Desktop cleans them up in the meantime, unless the user has typed since. When "Senden"
    /// was tapped during the dictation, the field goes out as soon as the words (cleaned, if wanted) are in it; when
    /// nothing was understood, a banner says so instead of sending nothing in silence.
    private func toggleDictation() async {
        if voice.listening { UsageRecorder.shared.record("chat", "diktat beendet", session: key, kind: "diktat"); voice.stopListening(); return }
        guard !dictating else { return }  // a second tap while the first one still starts (permission, vocabulary)
        dictating = true
        defer { dictating = false }
        if let msg = await voice.authorize() { error = msg; return }
        if !vocabLoaded { vocabLoaded = true; await model.loadVocab(into: voice) }
        let clean = ChatPrefs.cleanDictation
        if clean { model.cleanWarm() }
        let before = input
        sendAfterDictation = false
        var raw = ""
        var failure: String?
        UsageRecorder.shared.record("chat", "diktat gestartet", session: key, kind: "diktat")
        do { raw = try await voice.listen() } catch { failure = error.localizedDescription }
        if raw.isEmpty { UsageRecorder.shared.record("chat", "diktat leer", session: key, kind: "diktat", error: failure) }
        else { UsageRecorder.shared.content("chat", "diktiert", session: key, kind: "diktat", text: raw) }
        if !raw.isEmpty {
            let inserted = join(input, raw)
            input = inserted
            if !sendAfterDictation { focused = true }
            if clean, let cleaned = await model.cleanDictation(raw, before: before, session: key), input == inserted {
                input = join(before, cleaned)
            }
        }
        let sendNow = sendAfterDictation
        sendAfterDictation = false
        sending = false
        if sendNow {
            switch DictationSend.afterDictation(field: input, failure: failure) {
            case .send(let t): await send(t)
            case .nothing(let why): error = why
            }
        } else if let failure {
            error = failure
        }
        // Spotify bleibt pausiert, solange der diktierte Text noch auf Senden wartet; sonst gleich weiter
        dictated = !sendNow && !raw.isEmpty && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !dictated { voice.releaseAudio() }
    }

    // MARK: attachments

    private func uploadPicked(_ provider: NSItemProvider) async {
        let stamp = Int(Date().timeIntervalSince1970)
        uploadInfo = "Lade Auswahl…"
        let media: PickedMedia
        do { media = try await PickedMedia.load(provider) } catch { uploadInfo = ""; self.error = error.localizedDescription; return }
        uploadInfo = ""
        switch media {
        case .movie(let url):
            defer { try? FileManager.default.removeItem(at: url) }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Attach.maxBytes else { error = "Das Video ist größer als 50 MB"; return }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { error = "Video konnte nicht gelesen werden"; return }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            await upload(name: "video-\(stamp).\(ext)", data: data)
        case .image(let data):
            // The name follows the bytes (with .compatible iOS hands over JPEG for a HEIC original).
            let type = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) }
            let ext = type?.preferredFilenameExtension ?? "jpg"
            await upload(name: "foto-\(stamp).\(ext)", data: data, photo: true, mime: type?.preferredMIMEType)
        }
    }

    private func uploadClipboard() async {
        guard let img = UIPasteboard.general.image, let d = img.pngData() else { error = "Kein Bild in der Zwischenablage"; return }
        await upload(name: "zwischenablage-\(Int(Date().timeIntervalSince1970)).png", data: d, photo: true, mime: "image/png")
    }

    private func uploadFile(_ url: URL) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "Datei konnte nicht gelesen werden"; return }
        await upload(name: url.lastPathComponent, data: data)
    }

    /// `photo`: from the picker, the camera or the clipboard; a long edge above 2048 px is scaled down first (GIFs never).
    private func upload(name: String, data: Data, photo: Bool = false, mime: String? = nil) async {
        var name = name, data = data
        if photo { (name, data) = await Task.detached(priority: .userInitiated) { [n = name, d = data] in AttachPrep.prepared(name: n, data: d, mime: mime) }.value }
        guard data.count <= Attach.maxBytes else { error = "Datei ist größer als 50 MB"; return }
        let label = name
        uploadInfo = "Lade \(label) hoch…"
        do {
            let path = try await model.upload(name: label, data: data) { p in Task { @MainActor in uploadInfo = "Lade \(label) hoch… \(Int(p * 100)) %" } }
            UsageRecorder.shared.record("chat", "anhang hochgeladen", session: key, kind: photo ? "foto" : "datei", length: data.count, detail: path)
            let head = input.trimmingCharacters(in: .whitespacesAndNewlines)
            input = (head.isEmpty ? "" : head + "\n") + path + "\n"
            uploadInfo = ""
            focused = true
        } catch {
            uploadInfo = ""; self.error = error.localizedDescription
            UsageRecorder.shared.record("chat", "anhang fehlgeschlagen", session: key, kind: photo ? "foto" : "datei", length: data.count, error: error.localizedDescription)
        }
    }
}

/// Model, effort and context size from the newest request of the session.
struct ChatContext: Equatable {
    var model = ""
    var effort = ""
    var tokens = 0
}

// MARK: message rendering

struct MessageRow: View {
    let m: TMessage
    var highlighted = false
    @State private var toolsOpen = false
    @Environment(\.chatActions) private var actions

    var body: some View {
        content
            .background(highlighted ? Color.yellow.opacity(0.25) : Color.clear)
            .animation(.easeInOut, value: highlighted)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                actions.menu(m)
            }
    }

    @ViewBuilder private var content: some View {
        switch m.role {
        case "user":
            HStack { Spacer(minLength: 40)
                Text(MarkdownText.linkified(AttributedString(m.text))).padding(10)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 14)) }
            .padding(.horizontal)
        case "system":
            Text(m.text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.horizontal)
        case "tool":
            toolRow
        default:
            VStack(alignment: .leading, spacing: 6) {
                if !m.text.isEmpty { MarkdownText(text: m.text, selectable: false) }
                if !m.tools.isEmpty { toolRow }
                if !m.files.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(m.files, id: \.path) { f in FileChip(ref: RemoteRef(f), onOpen: actions.openFile) }
                    }
                }
                if !m.text.isEmpty { speakButton }
            }
            .padding(.horizontal)
        }
    }

    /// Das kleine Lautsprecher-Symbol unter einer Antwort: liest sie vor (Langdruck-Menü: auch nur die Frage).
    private var speakButton: some View {
        Button { actions.speak(m.text) } label: {
            Image(systemName: "speaker.wave.2").font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vorlesen")
    }

    private func pathButton(_ t: ToolCall, path: String) -> some View {
        let parts = ToolPaths.split(summary: t.summary, path: path)
        return HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
            Button { actions.openPath(path) } label: { Text(parts.name).font(.system(.caption, design: .monospaced)).underline() }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            Text("\(t.name) · \(parts.rest)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder private var toolRow: some View {
        if m.tools.count == 1, let p = m.tools[0].path, ToolPaths.isFileTool(m.tools[0].name) {
            pathButton(m.tools[0], path: p).padding(.horizontal)
        } else if !m.tools.isEmpty {
            DisclosureGroup(isExpanded: $toolsOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(m.tools.enumerated()), id: \.offset) { _, t in
                        if let p = t.path, ToolPaths.isFileTool(t.name) {
                            pathButton(t, path: p)
                        } else {
                            Text("\(t.name): \(t.summary)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(4)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(m.tools.count == 1 ? "\(m.tools[0].name) · \(m.tools[0].summary)" : "\(m.tools.count) Werkzeugaufrufe",
                      systemImage: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal)
        } else if !m.text.isEmpty {
            Text(m.text).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(6).padding(.horizontal)
        }
    }
}

struct AsksCard: View {
    let text: String
    var speak: ((String) -> Void)? = nil
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Die Sitzung fragt dich", systemImage: "questionmark.bubble").font(.subheadline.weight(.semibold))
                Spacer()
                if let speak { SpeakQuestionButton { speak(text) } }
            }
            Text(text).font(.callout)
            Button("Erledigt", action: done).buttonStyle(.bordered)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
    }
}

/// „Frage vorlesen“ an einer Fragekarte: nur die Frage mit ihren Optionen, nicht der Rest des Chats.
struct SpeakQuestionButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "speaker.wave.2") }
            .buttonStyle(.borderless)
            .accessibilityLabel("Frage vorlesen")
    }
}

struct QuestionCard: View {
    let q: Question
    var speak: ((String) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(q.header.isEmpty ? "Frage" : q.header, systemImage: "questionmark.circle").font(.subheadline.weight(.semibold))
                Spacer()
                if let speak { SpeakQuestionButton { speak(ReadAloud.spoken(question: q)) } }
            }
            Text(q.text)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                Text("\(i + 1). \(o.label)").font(.callout)
            }
            Text("Antwortkarte erscheint, sobald der Bildschirm geladen ist.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
    }
}

/// Search over the whole transcript of one session (rpc `transcript_search`); a hit jumps there in the chat.
struct ChatSearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sessionKey: String
    let onPick: (String, Int) -> Void

    init(sessionKey: String, initial: String = "", onPick: @escaping (String, Int) -> Void) {
        self.sessionKey = sessionKey
        self.onPick = onPick
        _query = State(initialValue: initial)
    }

    @State private var query: String
    @State private var hits: [JSON] = []
    @State private var searched = ""
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                    Button {
                        onPick(h.str("id"), h["index"].int ?? 0)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(h.str("role") == "user" ? "Du" : "Agent").font(.caption.weight(.semibold))
                                Spacer()
                                Text(TermText.ago(h.num("ts"))).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(h.str("snippet")).font(.callout).lineLimit(4)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !searching && hits.isEmpty && searched.count >= 2 && error == nil {
                    Text("Nichts gefunden für „\(searched)“").foregroundStyle(.secondary)
                }
                if searching { HStack { Spacer(); ProgressView(); Spacer() } }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Im Verlauf suchen")
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if !Task.isCancelled { await run() }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { hits = []; searched = ""; return }
        searching = true; defer { searching = false }
        do {
            let r = try await model.rpc("transcript_search", ["key": .string(sessionKey), "query": .string(q), "limit": 100], timeout: 20)
            hits = r["matches"].array
            searched = q
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
