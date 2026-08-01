//
//  LockScreenLyricsTranslationBridge.swift
//  boringNotch
//
//  Translation flow adapted from Lyric Fever.
//

import SwiftUI

#if canImport(Translation)
import Translation

@available(macOS 15.0, *)
struct LockScreenLyricsTranslationBridge: View {
    @ObservedObject var musicManager: MusicManager
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: refreshConfiguration)
            .onChange(of: musicManager.lyricTranslationToken) { _, _ in
                refreshConfiguration()
            }
            .translationTask(configuration) { session in
                await musicManager.translateCurrentLyrics(using: session)
            }
            .accessibilityHidden(true)
    }

    private func refreshConfiguration() {
        guard !musicManager.lyricLines.isEmpty else {
            configuration = nil
            musicManager.clearTranslatedLyrics()
            return
        }

        let sourceLanguage = musicManager.detectLyricsLanguage()
        let targetLanguage = Locale.Language(identifier: "en")

        if sourceLanguage?.minimalIdentifier == targetLanguage.minimalIdentifier {
            configuration = nil
            musicManager.clearTranslatedLyrics()
            return
        }

        configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
    }
}
#endif
