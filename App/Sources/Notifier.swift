import Foundation
import UserNotifications
import RelayCore

/// The notification settings from UserDefaults (the settings section uses the same keys through `@AppStorage`).
enum NotifyDefaults {
    static func prefs() -> NotifyPrefs {
        let d = UserDefaults.standard
        var p = NotifyPrefs()
        p.ready = d.string(forKey: "notifyReady") ?? "sound"
        p.input = d.string(forKey: "notifyInput") ?? "popup"
        p.auto = d.string(forKey: "notifyAuto") ?? "tasks"
        p.quietAtDesk = d.object(forKey: "quietAtDesk") as? Bool ?? true
        p.quietHours = d.object(forKey: "quietHours") as? Bool ?? false
        p.quietFrom = d.object(forKey: "quietFrom") as? Int ?? 22 * 60
        p.quietTo = d.object(forKey: "quietTo") as? Int ?? 7 * 60
        return p
    }
    static var actionAuth: Bool { UserDefaults.standard.object(forKey: "actionAuth") as? Bool ?? true }
    static var enabled: Bool { UserDefaults.standard.object(forKey: "notify") as? Bool ?? true }
}

/// Posts and removes local notifications. `silent` lands in the list without sound (interruption level passive).
enum Notifier {
    static func post(id: String, title: String, body: String, userInfo: [String: String] = [:], category: String? = nil,
                     thread: String? = nil, silent: Bool = false) {
        guard NotifyDefaults.enabled else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = String(body.prefix(300))
        if silent { c.sound = nil; c.interruptionLevel = .passive } else { c.sound = .default }
        if !userInfo.isEmpty { c.userInfo = userInfo }
        if let thread { c.threadIdentifier = thread }
        if let category { c.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    static func remove(_ ids: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
}
