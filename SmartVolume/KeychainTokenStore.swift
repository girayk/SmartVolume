import Foundation
import Security

/// Stores each monitor's pairing token as a generic password.
/// Keychain calls can block, so they run on a private serial queue, never the caller's thread.
/// The queue is serial, so a read always sees the saves and deletes made before it.
public final class KeychainTokenStore: TokenStoring {
    private let service: String
    private let queue = DispatchQueue(label: "com.scormy.smartvolume.keychain")

    public init(service: String = "com.scormy.smartvolume.token") {
        self.service = service
    }

    public func token(for deviceID: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let token = self.read(deviceID)
            DispatchQueue.main.async { completion(token) }
        }
    }

    public func save(_ token: String, for deviceID: String) {
        queue.async {
            self.remove(deviceID)
            var query = self.baseQuery(deviceID)
            query[kSecValueData as String] = Data(token.utf8)
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public func delete(for deviceID: String) {
        queue.async { self.remove(deviceID) }
    }

    // MARK: - On the queue

    private func read(_ deviceID: String) -> String? {
        var query = baseQuery(deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func remove(_ deviceID: String) {
        SecItemDelete(baseQuery(deviceID) as CFDictionary)
    }

    private func baseQuery(_ deviceID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
        ]
    }
}
