import AppKit

let app = NSApplication.shared
// Unit tests run inside the app, so skip the real startup there.
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
let delegate = isRunningTests ? nil : AppDelegate()
app.delegate = delegate
app.run()
