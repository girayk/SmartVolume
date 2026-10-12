import Foundation

public enum SmartVolumeInfo {
    /// The version set in Xcode (target > General > Version).
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    public static let appName = "SmartVolume"
    public static let repositoryURL = "https://github.com/girayk/SmartVolume"
}
