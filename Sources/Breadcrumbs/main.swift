import AppKit
import SwiftUI

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        FixtureSnapshots.run(dir: args[i + 1])
    }
    exit(0)
}
if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        PNG.render(AppIconView(), dark: false, to: URL(fileURLWithPath: args[i + 1]))
    }
    exit(0)
}
BreadcrumbsApp.main()
