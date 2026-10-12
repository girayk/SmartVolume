public enum AudioTransport: Equatable {
    case builtIn, displayPort, hdmi, usb, bluetooth, other
}

public struct AudioOutput: Equatable {
    public let uid: String
    public let name: String
    public let transport: AudioTransport

    public init(uid: String, name: String, transport: AudioTransport) {
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}

public struct PairedMonitor: Codable, Equatable {
    public let deviceID: String
    public let host: String
    public let name: String
    public var outputUID: String?

    public init(deviceID: String, host: String, name: String, outputUID: String? = nil) {
        self.deviceID = deviceID
        self.host = host
        self.name = name
        self.outputUID = outputUID
    }
}

extension PairedMonitor {
    /// The name as people should see it. Samsung reports names HTML-escaped and
    /// sometimes prefixed with "[Monitor]" or "[TV]".
    public var displayName: String { DeviceName.clean(name) }
}

public enum DeviceName {
    private static let entities = [
        "&quot;": "\"", "&#34;": "\"", "&apos;": "'", "&#39;": "'",
        "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&amp;": "&",
    ]

    public static func clean(_ raw: String) -> String {
        var name = raw
        for (entity, character) in entities where entity != "&amp;" {
            name = name.replacingOccurrences(of: entity, with: character)
        }
        name = name.replacingOccurrences(of: "&amp;", with: "&")
        for prefix in ["[Monitor]", "[TV]"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}

public enum OutputMatcher {
    public static func isMonitor(_ output: AudioOutput?, paired: PairedMonitor?) -> Bool {
        guard let output, let paired else { return false }
        if let uid = paired.outputUID {
            return output.uid == uid
        }
        guard output.transport == .displayPort || output.transport == .hdmi else { return false }
        let name = output.name.lowercased()
        return name.contains(paired.displayName.lowercased()) || name.contains("samsung")
    }
}
