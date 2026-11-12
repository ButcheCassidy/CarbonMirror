// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if canImport(os)
import os
#else
import Foundation
#endif

/// Metadata-only logging. Messages are compile-time strings; metadata values are app-generated facts
/// (ports, codes, counts) — never phone content, clipboard text, keys or typed input.
public enum Log {
    public static let subsystem = "com.nomadicrebel.carbonmirror"

    /// Log categories.
    public enum Category: String, Sendable {
        case app, ui, transport, adb, security, media, input
    }

    /// Records an informational event.
    public static func info(_ category: Category, _ message: StaticString, _ metadata: KeyValuePairs<String, String> = [:]) {
        emit(category, message, metadata, isError: false)
    }

    /// Records a failure.
    public static func error(_ category: Category, _ message: StaticString, _ metadata: KeyValuePairs<String, String> = [:]) {
        emit(category, message, metadata, isError: true)
    }

    private static func emit(_ category: Category, _ message: StaticString, _ metadata: KeyValuePairs<String, String>, isError: Bool) {
        let meta = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let line = meta.isEmpty ? "\(message)" : "\(message) \(meta)"
        #if canImport(os)
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        if isError {
            logger.error("\(line, privacy: .public)")
        } else {
            logger.info("\(line, privacy: .public)")
        }
        #else
        if ProcessInfo.processInfo.environment["CM_LOG"] == "1" {
            FileHandle.standardError.write(Data("[\(category.rawValue)] \(isError ? "ERROR " : "")\(line)\n".utf8))
        }
        #endif
    }
}
