/// What to do with an intercepted key.
public enum InterceptAction: Equatable {
    /// Let macOS handle the key as if SmartVolume weren't running.
    case pass
    /// Swallow the key, optionally sending a command to the monitor.
    case swallow(send: RemoteKey?)
}

public enum InterceptPolicy {
    /// The event tap is on only when every condition holds; otherwise macOS keeps full control.
    public static func tapShouldBeActive(monitorIsOutput: Bool, link: LinkState, accessibilityGranted: Bool) -> Bool {
        monitorIsOutput && link == .connected && accessibilityGranted
    }

    public static func action(for event: MediaKeyEvent, tapActive: Bool) -> InterceptAction {
        guard tapActive else { return .pass }
        guard event.isDown else { return .swallow(send: nil) }
        switch event.key {
        case .volumeUp: return .swallow(send: .volUp)
        case .volumeDown: return .swallow(send: .volDown)
        case .mute: return .swallow(send: event.isRepeat ? nil : .mute)
        }
    }

    /// macOS disables a slow tap; turn it back on only if it should be running.
    public static func shouldReenableAfterSystemDisable(tapShouldBeActive: Bool) -> Bool {
        tapShouldBeActive
    }
}
