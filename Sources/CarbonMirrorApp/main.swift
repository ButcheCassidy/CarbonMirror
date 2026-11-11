#if os(macOS)
import AppKit
import CMUI

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate(arguments: CommandLine.arguments) }
app.delegate = delegate
app.run()
#else
import Foundation

FileHandle.standardError.write(Data("CarbonMirror is a macOS app; on Linux only the core libraries and tests build.\n".utf8))
exit(64)
#endif
