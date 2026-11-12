// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMUI

// Monochrome controls (spec A3.5): the app's own accent and highlight are Graphite, whatever the system accent is.
UserDefaults.standard.set(-1, forKey: "AppleAccentColor")
UserDefaults.standard.set("0.847059 0.847059 0.862745 Graphite", forKey: "AppleHighlightColor")
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate(arguments: CommandLine.arguments) }
app.delegate = delegate
app.run()
#else
import Foundation

FileHandle.standardError.write(Data("CarbonMirror is a macOS app; on Linux only the core libraries and tests build.\n".utf8))
exit(64)
#endif
