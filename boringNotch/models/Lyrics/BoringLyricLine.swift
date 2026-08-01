//
//  BoringLyricLine.swift
//  boringNotch
//
//  Portions adapted from Lyric Fever.
//

import Foundation

struct BoringLyricLine: Identifiable, Hashable {
    let id = UUID()
    let startTime: TimeInterval
    let words: String
    let romanizedWords: String

    init(startTime: TimeInterval, words: String, romanizedWords: String? = nil) {
        self.startTime = startTime
        self.words = words
        self.romanizedWords = romanizedWords ?? words
    }
}

struct LockScreenLyricDisplayLine: Identifiable, Hashable {
    enum Role: Hashable {
        case previous
        case current
        case upcoming(Int)
    }

    let id: String
    let role: Role
    let originalText: String
    let translatedText: String?

    var displayText: String {
        let candidate = translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? originalText : candidate
    }

    var subtitleText: String? {
        guard let translatedText,
              !translatedText.isEmpty,
              translatedText != originalText else {
            return nil
        }

        return originalText
    }
}

struct LockScreenLyricDisplayContext: Hashable {
    let previous: LockScreenLyricDisplayLine?
    let current: LockScreenLyricDisplayLine
    let upcoming: [LockScreenLyricDisplayLine]
    let currentID: String

    var displayLines: [LockScreenLyricDisplayLine] {
        var lines: [LockScreenLyricDisplayLine] = []
        if let previous {
            lines.append(previous)
        }
        lines.append(current)
        lines.append(contentsOf: upcoming)
        return lines
    }
}
