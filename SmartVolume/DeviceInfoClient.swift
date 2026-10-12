import Foundation

public struct DeviceInfo: Equatable {
    public let id: String
    public let name: String
    public let model: String

    public init(id: String, name: String, model: String) {
        self.id = id
        self.name = name
        self.model = model
    }
}

/// Reads a Samsung device's identity from `http://<host>:8001/api/v2/`.
public struct DeviceInfoClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func parse(_ data: Data) -> DeviceInfo? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let device = object["device"] as? [String: Any],
              let id = device["id"] as? String
        else { return nil }
        return DeviceInfo(
            id: id,
            name: DeviceName.clean((device["name"] as? String) ?? "Samsung monitor"),
            model: (device["modelName"] as? String) ?? ""
        )
    }

    public func fetch(host: String) async throws -> DeviceInfo {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { throw URLError(.badURL) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        let (data, _) = try await session.data(for: request)
        guard let info = Self.parse(data) else { throw URLError(.cannotParseResponse) }
        return info
    }
}
