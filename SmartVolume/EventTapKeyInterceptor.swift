import AppKit
import CoreGraphics

/// Captures the volume keys with a session event tap. While the tap is disabled,
/// macOS handles the keys on its own. In the App Store build the tap is listen-only
/// (see `KeyPermission`), so keys are observed but never swallowed.
public final class EventTapKeyInterceptor: KeyIntercepting {
    public private(set) var isEnabled = false
    public var onKey: ((MediaKeyEvent) -> InterceptAction)?
    public var onSend: ((RemoteKey) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Turns the underlying tap on or off. Replaced in tests.
    var tapEnabler: (Bool) -> Void = { _ in }

    /// The sandbox only allows listening, so macOS still handles the key too.
    static let tapOptions: CGEventTapOptions = .listenOnly

    public init() {
        tapEnabler = { [weak self] enabled in
            guard let tap = self?.tap else { return }
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled && tap == nil { createTap() }
        tapEnabler(enabled)
    }

    private func createTap() {
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<EventTapKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.process(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: Self.tapOptions,
            eventsOfInterest: systemDefined,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleSystemDisable()
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        return handle(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1) ? nil : Unmanaged.passUnretained(event)
    }

    /// Marks the interceptor enabled without creating a real tap.
    func markEnabledForTesting() {
        isEnabled = true
    }

    func handleSystemDisable() {
        if InterceptPolicy.shouldReenableAfterSystemDisable(tapShouldBeActive: isEnabled) {
            tapEnabler(true)
        }
    }

    /// Returns true when the event should be swallowed.
    func handle(subtype: Int16, data1: Int) -> Bool {
        guard let event = MediaKeyEvent.decode(subtype: subtype, data1: data1), let onKey else { return false }
        switch onKey(event) {
        case .pass:
            return false
        case .swallow(let key):
            if let key { onSend?(key) }
            return true
        }
    }
}
