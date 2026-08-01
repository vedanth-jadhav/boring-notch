//
//  LyricRomanizationService.swift
//  boringNotch
//
//  Romanizes Indic script lyrics (Gurmukhi → Hinglish, Devanagari → Hinglish).
//  Passes through Latin, CJK, Spanish, and other scripts unchanged.
//  Uses CFStringTransform for robust transliteration.
//

import Defaults
import Foundation
import NaturalLanguage

final class LyricRomanizationService {
    static let shared = LyricRomanizationService()

    private let languageRecognizer: NLLanguageRecognizer

    private init() {
        self.languageRecognizer = NLLanguageRecognizer()
    }

    /// Check if the lyric language code is one of the Indic scripts we romanize.
    func shouldRomanize(languageCode: String) -> Bool {
        let indicLanguages: Set<String> = ["pa", "hi", "mr", "bh", "sa", "ne", "gu", "bn", "or"]
        return indicLanguages.contains(languageCode)
    }

    /// Detect language from text and check if romanization is needed.
    func needsRomanization(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        guard let hypothesis = languageRecognizer.dominantLanguage else {
            return false
        }
        return shouldRomanize(languageCode: hypothesis.rawValue)
    }

    /// Check if text contains Indic unicode characters (fast pre-check).
    func containsIndicScript(_ text: String) -> Bool {
        for char in text {
            let scalars = char.unicodeScalars
            for scalar in scalars {
                switch scalar.value {
                case 0x0900...0x097F: return true // Devanagari
                case 0x0A00...0x0A7F: return true // Gurmukhi
                case 0x0B80...0x0BFF: return true // Tamil
                case 0x0C00...0x0C7F: return true // Telugu
                case 0x0C80...0x0CFF: return true // Kannada
                case 0x0D00...0x0D7F: return true // Malayalam
                case 0x0980...0x09FF: return true // Bengali
                case 0x0A80...0x0AFF: return true // Gujarati
                case 0x0B00...0x0B7F: return true // Oriya
                case 0x0D80...0x0DFF: return true // Sinhala
                default: continue
                }
            }
        }
        return false
    }

    /// Romanize text using Apple's built-in CFStringTransform.
    /// This handles all Indic conjuncts, vowel signs, halants natively.
    func romanize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        var success = false

        // Latin transliteration strips diacritics for a clean Hinglish-like output
        success = CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        guard success else { return text }

        // Strip combining marks (diacritics) for clean output
        success = CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        guard success else { return mutable as String }

        return mutable as String
    }

    /// Apply romanization to the entire multi-line lyrics string.
    func romanizeLyrics(_ lyrics: String) -> String {
        guard Defaults[.enableLyricRomanization], containsIndicScript(lyrics) else {
            return lyrics
        }
        return lyrics
            .components(separatedBy: .newlines)
            .map { romanize($0) }
            .joined(separator: "\n")
    }

    /// Romanize a single line only if it needs it.
    func applyIfNeeded(_ text: String) -> String {
        guard Defaults[.enableLyricRomanization], containsIndicScript(text) else {
            return text
        }
        return romanize(text)
    }

    /// Romanize a multi-line string only if it contains Indic script.
    func romanizeLyricsIfNeeded(_ lyrics: String) -> String {
        guard Defaults[.enableLyricRomanization], containsIndicScript(lyrics) else {
            return lyrics
        }
        return lyrics
            .components(separatedBy: .newlines)
            .map { romanize($0) }
            .joined(separator: "\n")
    }

    /// Batch romanize an array of lyric lines.
    func romanizeLinesIfNeeded(_ lines: [String]) -> [String] {
        guard Defaults[.enableLyricRomanization] else { return lines }
        guard lines.contains(where: { containsIndicScript($0) }) else { return lines }
        return lines.map { containsIndicScript($0) ? romanize($0) : $0 }
    }
}
