import AppKit
import SwiftUI
import MeridianKit

/// PLACEHOLDER. Owned by the UI workstream. Renders every surface in every scenario to PNG using mock data.
@MainActor
enum SnapshotRenderer {
    static func run(outputDirectory: URL) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        FileHandle.standardError.write(Data("SnapshotRenderer not implemented yet\n".utf8))
    }
}
