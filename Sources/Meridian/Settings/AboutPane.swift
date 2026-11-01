import SwiftUI
import AppKit

struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        if let build = info?["CFBundleVersion"] as? String, build != short { return "Version \(short) (\(build))" }
        return "Version \(short)"
    }

    /// The app icon from a real bundle; outside one (swift run) the system would show a generic folder, so
    /// the menu bar glyph stands in.
    @ViewBuilder private var icon: some View {
        if Bundle.main.bundleURL.pathExtension == "app" {
            Image(nsImage: NSApp.applicationIconImage).resizable()
        } else {
            Image(nsImage: StatusItemController.glyph).renderingMode(.template).resizable().scaledToFit()
                .padding(8).foregroundStyle(.primary)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            icon
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            Text("Meridian").font(.title.weight(.semibold))
            Text(version).foregroundStyle(.secondary)
            Text("A quiet system monitor that shows the one thing that matters, and gets out of the way.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
                .padding(.top, 2)
            Link("github.com/Puneetspyne/Meridian", destination: URL(string: "https://github.com/Puneetspyne/Meridian")!)
                .padding(.top, 6)
            Text("Released under the MIT License. No analytics, no account.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
