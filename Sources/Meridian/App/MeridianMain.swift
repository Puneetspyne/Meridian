import AppKit
import MeridianKit

/// Entry point. No SwiftUI `App` scene on purpose: panels over the notch and in screen corners are
/// AppKit `NSPanel`s, and AppKit owns the lifecycle so we control activation, levels and Spaces precisely.
@main
enum MeridianMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            // Renders every surface to PNG with mock data. Used for the README and for visual review in CI.
            SnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: args[i + 1]))
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
