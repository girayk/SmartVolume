import Darwin
import Foundation

/// Finds Samsung remote-control receivers on the local network with an SSDP search.
public final class SSDPDiscovery {
    public static let searchMessage =
        "M-SEARCH * HTTP/1.1\r\n" +
        "HOST: 239.255.255.250:1900\r\n" +
        "MAN: \"ssdp:discover\"\r\n" +
        "MX: 2\r\n" +
        "ST: urn:samsung.com:device:RemoteControlReceiver:1\r\n\r\n"

    public init() {}

    public static func parseLocationHost(_ response: String) -> String? {
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("location:") else { continue }
            let value = trimmed.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
            return URL(string: value)?.host
        }
        return nil
    }

    public func discover(timeout: TimeInterval = 3) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.search(timeout: timeout))
            }
        }
    }

    private static func search(timeout: TimeInterval) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &address.sin_addr)

        let message = Array(searchMessage.utf8)
        for _ in 0..<2 {
            _ = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, message, message.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var hosts: [String] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0,
                  let response = String(bytes: buffer[0..<count], encoding: .utf8),
                  let host = parseLocationHost(response),
                  !hosts.contains(host)
            else { continue }
            hosts.append(host)
        }
        return hosts
    }
}
