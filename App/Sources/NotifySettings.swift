import SwiftUI
import RelayCore

/// Settings section "Mitteilungen": what rings, what stays quiet, quiet hours, protected actions.
struct NotifySettingsSection: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("notify") private var enabled = true
    @AppStorage("notifyReady") private var ready = "sound"
    @AppStorage("notifyInput") private var input = "popup"
    @AppStorage("notifyAuto") private var auto = "tasks"
    @AppStorage("quietAtDesk") private var quietAtDesk = true
    @AppStorage("quietHours") private var quietHours = false
    @AppStorage("quietFrom") private var from = 22 * 60
    @AppStorage("quietTo") private var to = 7 * 60
    @AppStorage("actionAuth") private var actionAuth = true

    private func date(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        } set: { d in
            minutes.wrappedValue = QuietHours.minuteOfDay(d)
        }
    }

    var body: some View {
        Section("Mitteilungen") {
            Toggle("Mitteilungen anzeigen", isOn: $enabled)
            Text("iOS hält keine Verbindung im Hintergrund offen. Ist Relay zu, schaut die App ab und zu kurz nach (Hintergrundaktualisierung, iOS bestimmt wann, meist alle 15 bis 60 Minuten). Dafür muss unter Einstellungen → Allgemein → Hintergrundaktualisierung Relay erlaubt sein. Aus einer Mitteilung kannst du direkt antworten, „Erledigt“ setzen oder die Sitzung stummschalten.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Sitzung fertig", selection: $ready) {
                Text("Mit Ton").tag("sound"); Text("Still").tag("silent"); Text("Aus").tag("off")
            }
            Picker("Braucht Eingabe", selection: $input) {
                Text("Hinweis").tag("popup"); Text("Still").tag("silent")
            }
            Picker("Eigene Züge des Agenten", selection: $auto) {
                Text("Still, solange Aufgaben laufen").tag("tasks"); Text("Wie „fertig“").tag("same"); Text("Immer still").tag("silent")
            }
            Text("Gemeint sind Züge, die der Agent selbst gestartet hat (eine Hintergrundaufgabe endete, ein anderer Agent schrieb ihm). Fragen klingeln immer.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Still, wenn ich am PC bin", isOn: $quietAtDesk)
            Toggle("Ruhezeiten", isOn: $quietHours)
            if quietHours {
                DatePicker("Von", selection: date($from), displayedComponents: .hourAndMinute)
                DatePicker("Bis", selection: date($to), displayedComponents: .hourAndMinute)
                Text(from == to ? "Von und Bis sind gleich: nie still." : "„Fertig“ und „beendet“ landen zwischen \(QuietHours.label(from)) und \(QuietHours.label(to)) still in der Liste. Fragen klingeln immer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Aktionen brauchen entsperrtes Gerät", isOn: $actionAuth)
            Text("Antworten, „Weiter“ und „Freigeben“ in einer Mitteilung lassen sich dann nur bei entsperrtem iPhone auslösen. „Freigeben“ verlangt das immer.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.muted.isEmpty {
                Button("Alle \(model.muted.count) stummgeschalteten Sitzungen wieder laut") { model.muted = [] }
            }
        }
        .onChange(of: actionAuth) { _, _ in AppModel.registerNotificationActions() }
    }
}
