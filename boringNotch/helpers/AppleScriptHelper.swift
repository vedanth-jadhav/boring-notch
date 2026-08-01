//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    // Cache compiled NSAppleScript instances so scripts compile once, not on every call
    private static var scriptCache: [String: NSAppleScript] = [:]
    private static let cacheLock = NSLock()
    private static let cacheQueue = DispatchQueue(label: "com.boringnotch.applescript-cache")

    /// Return a cached, pre-compiled NSAppleScript for the given source text.
    /// Compilation is done once and reused for subsequent calls.
    private static func compiledScript(_ source: String) -> NSAppleScript {
        cacheQueue.sync {
            if let cached = scriptCache[source] { return cached }
            let script = NSAppleScript(source: source)!
            scriptCache[source] = script
            return script
        }
    }

    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        let script = compiledScript(scriptText)
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(returning: descriptor)
                }
            }
        }
    }

    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
