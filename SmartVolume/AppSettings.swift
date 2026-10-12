import Foundation

public enum PresenceMode: String, Codable, CaseIterable {
    case dock, menuBar, background

    public var title: String {
        switch self {
        case .dock: return "Dock"
        case .menuBar: return "Menu bar"
        case .background: return "Background"
        }
    }
}

public enum PresenceRules {
    /// Background mode hides the app entirely, so it is only offered once pairing works.
    public static func allowedModes(paired: Bool) -> [PresenceMode] {
        paired ? [.dock, .menuBar, .background] : [.dock, .menuBar]
    }
}

public protocol SettingsStore: AnyObject {
    var presenceMode: PresenceMode { get set }
    var startAtLogin: Bool { get set }
    var pairedMonitor: PairedMonitor? { get set }
    var setupComplete: Bool { get set }
}

public final class UserDefaultsSettingsStore: SettingsStore {
    private enum Key {
        static let presenceMode = "presenceMode"
        static let startAtLogin = "startAtLogin"
        static let pairedMonitor = "pairedMonitor"
        static let setupComplete = "setupComplete"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var presenceMode: PresenceMode {
        get { defaults.string(forKey: Key.presenceMode).flatMap(PresenceMode.init(rawValue:)) ?? .menuBar }
        set { defaults.set(newValue.rawValue, forKey: Key.presenceMode) }
    }

    public var startAtLogin: Bool {
        get { defaults.object(forKey: Key.startAtLogin) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.startAtLogin) }
    }

    public var pairedMonitor: PairedMonitor? {
        get { defaults.data(forKey: Key.pairedMonitor).flatMap { try? JSONDecoder().decode(PairedMonitor.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.pairedMonitor)
            } else {
                defaults.removeObject(forKey: Key.pairedMonitor)
            }
        }
    }

    public var setupComplete: Bool {
        get { defaults.bool(forKey: Key.setupComplete) }
        set { defaults.set(newValue, forKey: Key.setupComplete) }
    }
}

public final class InMemorySettingsStore: SettingsStore {
    public var presenceMode: PresenceMode = .menuBar
    public var startAtLogin = true
    public var pairedMonitor: PairedMonitor?
    public var setupComplete = false

    public init() {}
}
