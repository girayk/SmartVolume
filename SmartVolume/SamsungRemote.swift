import Foundation

public enum RemoteKey: String {
    case volUp = "KEY_VOLUP"
    case volDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
}

/// Samsung's network remote protocol, shared by Samsung TVs and Smart Monitors.
public enum SamsungRemote {
    public enum Incoming: Equatable {
        case connected(token: String?)
        case unauthorized
        /// Nobody answered the Allow prompt on the monitor in time.
        case timedOut
        case other
    }

    public static func url(host: String, appName: String, token: String?, scheme: String = "wss", port: Int = 8002) -> URL {
        let name = Data(appName.utf8).base64EncodedString()
        var string = "\(scheme)://\(host):\(port)/api/v2/channels/samsung.remote.control?name=\(name)"
        if let token, let encoded = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            string += "&token=\(encoded)"
        }
        return URL(string: string)!
    }

    public static func clickCommand(_ key: RemoteKey) -> Data {
        let message: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key.rawValue,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
    }

    public static func parse(_ text: String) -> Incoming {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = object["event"] as? String
        else { return .other }
        switch event {
        case "ms.channel.connect":
            let token = (object["data"] as? [String: Any])?["token"] as? String
            return .connected(token: token)
        case "ms.channel.unauthorized":
            return .unauthorized
        case "ms.channel.timeOut":
            return .timedOut
        default:
            return .other
        }
    }
}
