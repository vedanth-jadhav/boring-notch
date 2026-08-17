from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    source = p.read_text()
    if new in source:
        return
    if old not in source:
        raise SystemExit(f"pattern not found in {path}")
    p.write_text(source.replace(old, new, 1))

# Do not let an open Octave tab reinterpret Spotify/Apple Music as Octave.
replace_once(
    "boringNotch/MediaControllers/NowPlayingController.swift",
    '''    private let base: NowPlayingController\n    private var cancellable: AnyCancellable?\n    private var detectionGeneration = 0\n''',
    '''    private let base: NowPlayingController\n    private var cancellable: AnyCancellable?\n    private var detectionGeneration = 0\n\n    private static let supportedBrowserBundleIdentifiers: Set<String> = [\n        "com.apple.Safari",\n        "com.google.Chrome",\n        "com.brave.Browser",\n        "com.microsoft.edgemac"\n    ]\n'''
)
replace_once(
    "boringNotch/MediaControllers/NowPlayingController.swift",
    '''    private func acceptIfOctaveIsOpen(_ state: PlaybackState) {\n        detectionGeneration &+= 1\n        let generation = detectionGeneration\n        Task { [weak self] in\n            let detected = await OctaveBrowserDetector.shared.hasOctaveTab()\n''',
    '''    private func acceptIfOctaveIsOpen(_ state: PlaybackState) {\n        // Never reinterpret a native player (Spotify, Apple Music, etc.) as Octave just\n        // because an Octave tab happens to be open in the background.\n        guard Self.supportedBrowserBundleIdentifiers.contains(state.bundleIdentifier) else {\n            var idle = PlaybackState(bundleIdentifier: Self.syntheticBundleIdentifier)\n            idle.isPlaying = false\n            playbackState = idle\n            return\n        }\n\n        detectionGeneration &+= 1\n        let generation = detectionGeneration\n        Task { [weak self] in\n            let detected = await OctaveBrowserDetector.shared.hasOctaveTab()\n'''
)

# Give the selected first-party Octave lyric source a genuine first attempt before
# generic providers race. Generic providers remain a resilient fallback.
lyrics_path = Path("boringNotch/managers/Lyrics/LyricFeverLyricsService.swift")
source = lyrics_path.read_text()
old = '''        // Fast parallel fetch across all applicable providers — take the first valid result.\n        let providers = networkLyricProviders(trackID: cleanedTrackID, bundleIdentifier: bundleIdentifier)\n        guard !providers.isEmpty else { return [] }\n\n        let result: [BoringLyricLine]? = await withTaskGroup(of: [BoringLyricLine]?.self) { group in\n'''
new = '''        let isOctave = bundleIdentifier == OctaveStreamingController.syntheticBundleIdentifier\n\n        // When Octave is selected, its own synced-lyrics source gets first refusal. This\n        // preserves provider identity while retaining the generic services as fallback.\n        if isOctave, let octaveLines = await fetchLines(\n            from: octaveProvider,\n            title: cleanedTitle,\n            artist: cleanedArtist,\n            album: cleanedAlbum,\n            trackID: cleanedTrackID,\n            durationMS: durationMS\n        ) {\n            cacheQueue.sync { lyricsCache[cKey] = octaveLines }\n            return octaveLines\n        }\n\n        // Fast parallel fallback across the remaining applicable providers.\n        let providers = networkLyricProviders(\n            trackID: cleanedTrackID,\n            bundleIdentifier: bundleIdentifier,\n            includeOctave: false\n        )\n        guard !providers.isEmpty else { return [] }\n\n        let result: [BoringLyricLine]? = await withTaskGroup(of: [BoringLyricLine]?.self) { group in\n'''
if new not in source:
    if old not in source:
        raise SystemExit("lyrics fetch block not found")
    source = source.replace(old, new, 1)

old2 = '''    private func networkLyricProviders(trackID: String?, bundleIdentifier: String?) -> [LyricFeverLyricProvider] {\n        var providers: [LyricFeverLyricProvider] = []\n\n        if bundleIdentifier == OctaveStreamingController.syntheticBundleIdentifier {\n            providers.append(octaveProvider)\n        }\n'''
new2 = '''    private func fetchLines(\n        from provider: LyricFeverLyricProvider,\n        title: String,\n        artist: String,\n        album: String,\n        trackID: String?,\n        durationMS: Int\n    ) async -> [BoringLyricLine]? {\n        do {\n            let lyrics = try await provider.fetchNetworkLyrics(\n                trackName: title,\n                trackID: trackID ?? "",\n                currentlyPlayingArtist: artist,\n                currentAlbumName: album\n            )\n            let lines = lyrics.processed(withSongName: title, duration: durationMS).lyrics\n                .filter { !$0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }\n                .map { BoringLyricLine(startTime: $0.startTimeMS / 1000, words: $0.words) }\n                .sorted { $0.startTime < $1.startTime }\n            return lines.count > 1 ? lines : nil\n        } catch {\n            return nil\n        }\n    }\n\n    private func networkLyricProviders(\n        trackID: String?,\n        bundleIdentifier: String?,\n        includeOctave: Bool = true\n    ) -> [LyricFeverLyricProvider] {\n        var providers: [LyricFeverLyricProvider] = []\n\n        if includeOctave, bundleIdentifier == OctaveStreamingController.syntheticBundleIdentifier {\n            providers.append(octaveProvider)\n        }\n'''
if new2 not in source:
    if old2 not in source:
        raise SystemExit("provider block not found")
    source = source.replace(old2, new2, 1)
lyrics_path.write_text(source)

print("Octave integration refinements applied")
