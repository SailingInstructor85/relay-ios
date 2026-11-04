import SwiftUI
import RelayCore

/// The session's live terminal (tmux capture, polled) with a key bar: for pickers, questions and anything the cards miss.
struct ScreenView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var text = ""
    @State private var menu: ScreenMenu?
    @State private var input = ""
    @State private var error: String?
    @State private var fontSize: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Text(text.isEmpty ? "Lade Bildschirm…" : text)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color.black)
                .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottomLeading) }
            }
            if let m = menu { MenuCard(menu: m, session: session) { await refresh() }.padding(.vertical, 6) }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red).padding(4) }
            keyBar
            HStack {
                TextField("Text tippen (ohne Enter)", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                Button("Senden") { Task { await sendText(enter: false) } }.disabled(input.isEmpty)
                Button("⏎") { Task { await sendText(enter: true) } }.disabled(input.isEmpty)
            }.padding(8)
        }
        .navigationTitle(session.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button { fontSize = max(7, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                    Button { fontSize = min(16, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private var keyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Group { key("Esc", ["Escape"]); key("⏎", ["Enter"]); key("↑", ["Up"]); key("↓", ["Down"]); key("←", ["Left"]); key("→", ["Right"]) }
                Group { key("Tab", ["Tab"]); key("⇧Tab", ["BTab"]); key("Space", ["Space"]); key("^C", ["C-c"]) }
                ForEach(1...5, id: \.self) { n in key("\(n)", ["\(n)"]) }
                Group { key("⌫", ["BSpace"]); key("PgUp", ["PPage"]); key("PgDn", ["NPage"]) }
            }.padding(.horizontal, 8)
        }.padding(.top, 6)
    }

    private func key(_ label: String, _ keys: [String]) -> some View {
        Button(label) { Task { await press(keys) } }
            .font(.system(.footnote, design: .monospaced)).buttonStyle(.bordered)
    }

    private func press(_ keys: [String]) async {
        do { try await model.sendKeys(session, keys); try? await Task.sleep(nanoseconds: 250_000_000); await refresh() }
        catch { self.error = error.localizedDescription }
    }

    private func sendText(enter: Bool) async {
        do {
            _ = try await model.rpc("send", ["target": .string(session.target), "text": .string(input), "enter": .bool(enter), "force": true])
            input = ""
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    private func refresh() async {
        do {
            let r = try await model.rpc("screen", ["target": .string(session.target), "lines": 300, "escapes": false, "menu": true], timeout: 10)
            let t = TermText.stripANSI(r.str("text"))
            if t != text { text = t }
            let m = ScreenMenu.from(r["menu"])
            if m?.id != menu?.id || (m == nil) != (menu == nil) { menu = m }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// A menu the TUI shows (gateway tuimenu.py) as native buttons. Picks go as key steps with `expect_menu`, so a stale
/// card can never answer a newer dialog.
struct MenuCard: View {
    @EnvironmentObject var model: AppModel
    let menu: ScreenMenu
    let session: Session
    let refresh: () async -> Void
    @State private var typed = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !menu.title.isEmpty { Text(menu.title).font(.subheadline.weight(.semibold)) }
            if !menu.tabs.isEmpty { Text(menu.tabs.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            if !menu.body.isEmpty { Text(menu.body).font(.footnote).lineLimit(12) }
            if !menu.plan.isEmpty { DisclosureGroup("Plan anzeigen") { MarkdownText(text: menu.plan).font(.footnote) }.font(.footnote) }
            if !menu.box.isEmpty {
                Text(menu.box).font(.system(.caption, design: .monospaced)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            if !menu.text.isEmpty { Text(menu.text).font(.footnote).foregroundStyle(.secondary).lineLimit(8) }

            if menu.isPanel { panel } else { options }

            HStack {
                ForEach(Array(menu.actions.enumerated()), id: \.offset) { _, a in
                    Button(a.label) { Task { await steps(a.keys.map { JSON.string($0) }) } }.buttonStyle(.bordered).font(.caption)
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { Task { await steps(["Escape"], expect: false) } }.buttonStyle(.bordered).font(.caption)
            }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .disabled(busy)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.35)))
        .padding(.horizontal)
    }

    @ViewBuilder private var options: some View {
        ForEach(Array(menu.options.enumerated()), id: \.offset) { i, o in
            if o.input {
                VStack(alignment: .leading, spacing: 4) {
                    Text(o.label).font(.callout)
                    HStack {
                        TextField("Antwort eingeben", text: $typed).textFieldStyle(.roundedBorder)
                        Button("Senden") {
                            var s = menu.stepsToPick(i); if s.last == "Enter" { s.removeLast() }
                            s.append(.object(["text": .string(typed)])); s.append("Enter")
                            Task { await steps(s) }
                        }.disabled(typed.isEmpty)
                    }
                }
            } else {
                Button { Task { await steps(menu.stepsToPick(i)) } } label: {
                    HStack(alignment: .top) {
                        if let c = o.checked { Image(systemName: c ? "checkmark.square.fill" : "square") }
                        VStack(alignment: .leading, spacing: 2) {
                            Text((o.n.map { "\($0). " } ?? "") + o.label).font(.callout.weight(o.current || menu.cursorIndex == i ? .semibold : .regular))
                                .multilineTextAlignment(.leading)
                            if !o.description.isEmpty { Text(o.description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                        }
                        Spacer()
                        if o.current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
        if menu.otherN != nil && !menu.options.contains(where: { $0.input }) {
            HStack {
                TextField("Eigene Antwort", text: $typed).textFieldStyle(.roundedBorder)
                Button("Senden") {
                    guard let n = menu.otherN else { return }
                    Task { await steps([.string(String(n)), .object(["text": .string(typed)]), "Enter"]) }
                }.disabled(typed.isEmpty)
            }
        }
        if menu.multi || menu.scrolls || !menu.digits {
            HStack {
                Button("↑") { Task { await steps(["Up"], expect: false) } }
                Button("↓") { Task { await steps(["Down"], expect: false) } }
                Button("Auswählen ⏎") { Task { await steps(["Enter"]) } }
                if let s = menu.submit { Text("(\(s) unten in der Liste)").font(.caption2).foregroundStyle(.secondary) }
            }.buttonStyle(.bordered).font(.caption)
        }
    }

    @ViewBuilder private var panel: some View {
        ForEach(Array(menu.blocks.enumerated()), id: \.offset) { _, b in
            switch b {
            case .text(let t): Text(t).font(.footnote)
            case .box(let t), .mono(let t):
                ScrollView(.horizontal, showsIndicators: false) { Text(t).font(.system(.caption2, design: .monospaced)) }
            case .bar(let label, let pct, let text):
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(label).font(.caption); Spacer(); Text(text).font(.caption2).foregroundStyle(.secondary) }
                    ProgressView(value: Double(min(max(pct, 0), 100)), total: 100)
                }
            case .kv(let rows):
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack { Text(r.0).font(.caption).foregroundStyle(.secondary); Spacer(); Text(r.1).font(.caption) }
                }
            case .rows(let rows):
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack { Text((r.cursor ? "❯ " : "  ") + r.text).font(.caption.weight(r.cursor ? .semibold : .regular)); Spacer(); Text(r.detail).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        if menu.nav {
            HStack {
                Button("↑") { Task { await steps(["Up"], expect: false) } }
                Button("↓") { Task { await steps(["Down"], expect: false) } }
                Button("⏎") { Task { await steps(["Enter"]) } }
                if menu.tabs.count > 1 {
                    Button("◀") { Task { await steps(["Left"]) } }
                    Button("▶") { Task { await steps(["Right"]) } }
                }
            }.buttonStyle(.bordered).font(.caption)
        }
    }

    private func steps(_ s: [JSON], expect: Bool = true) async {
        guard !s.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            try await model.sendSteps(session, s, expectMenu: expect ? menu.id : nil)
            error = nil
            typed = ""
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refresh()
        } catch { self.error = error.localizedDescription; await refresh() }
    }
}
