/// A volume key on the Mac keyboard.
public enum MediaKey: Equatable {
    case volumeUp, volumeDown, mute
}

/// A decoded system-defined media key event (NSEvent type 14, subtype 8).
public struct MediaKeyEvent: Equatable {
    public let key: MediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }

    /// Decodes the `subtype` and `data1` fields of a system-defined NSEvent.
    /// Returns nil for anything that isn't a volume or mute key.
    public static func decode(subtype: Int16, data1: Int) -> MediaKeyEvent? {
        guard subtype == 8 else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let key: MediaKey
        switch keyCode {
        case 0: key = .volumeUp      // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown    // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute          // NX_KEYTYPE_MUTE
        default: return nil
        }
        let flags = data1 & 0xFFFF
        return MediaKeyEvent(
            key: key,
            isDown: ((flags & 0xFF00) >> 8) == 0x0A,
            isRepeat: (flags & 0x1) == 1
        )
    }
}
