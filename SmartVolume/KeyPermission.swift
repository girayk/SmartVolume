import CoreGraphics

/// The permission the volume-key tap needs.
///
/// SmartVolume is sandboxed for the Mac App Store, where Accessibility isn't available,
/// so it uses a listen-only tap that needs Input Monitoring. macOS then also shows its
/// own "volume unavailable" overlay on each press.
public enum KeyPermission {
    public static let settingsName = "Input Monitoring"

    public static var isGranted: Bool { CGPreflightListenEventAccess() }

    public static func prompt() { _ = CGRequestListenEventAccess() }
}
