from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    s = p.read_text()
    if new in s:
        return
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:80]!r}')
    p.write_text(s.replace(old, new, 1))

# Provider selection
replace_once(
    'boringNotch/models/Constants.swift',
    '    case youtubeMusic = "YouTube Music"\n',
    '    case youtubeMusic = "YouTube Music"\n    case octaveStreaming = "Octave Streaming"\n',
)

replace_once(
    'boringNotch/managers/MusicManager.swift',
    '        case .youtubeMusic:\n            newController = YouTubeMusicController()\n',
    '        case .youtubeMusic:\n            newController = YouTubeMusicController()\n        case .octaveStreaming:\n            newController = OctaveStreamingController()\n',
)

# Seek reconciliation for browser MediaSession players.
replace_once(
    'boringNotch/MediaControllers/NowPlayingController.swift',
    '    private var streamTask: Task<Void, Never>?\n',
    '    private var streamTask: Task<Void, Never>?\n    private var pendingSeek: (time: Double, issuedAt: Date)?\n',
)
replace_once(
    'boringNotch/MediaControllers/NowPlayingController.swift',
    '    func seek(to time: Double) async {\n        MRMediaRemoteSetElapsedTimeFunction(time)\n    }',
    '''    func seek(to time: Double) async {\n        let clamped = max(0, min(time, playbackState.duration > 0 ? playbackState.duration : time))\n        pendingSeek = (clamped, Date())\n\n        // Browser MediaSession seek handlers are asynchronous. Optimistically move the\n        // local timeline and reconcile against the next authoritative MediaRemote sample.\n        var updated = playbackState\n        updated.currentTime = clamped\n        updated.lastUpdated = Date()\n        playbackState = updated\n\n        MRMediaRemoteSetElapsedTimeFunction(clamped)\n    }''',
)
replace_once(
    'boringNotch/MediaControllers/NowPlayingController.swift',
    '''        if let elapsedTime = payload.elapsedTime {\n            newPlaybackState.currentTime = elapsedTime\n        } else if diff {''',
    '''        if let elapsedTime = payload.elapsedTime {\n            // A browser commonly emits one stale position sample immediately after a seek.\n            // Keep the requested position briefly so the seek bar cannot snap backwards.\n            if let pendingSeek,\n               Date().timeIntervalSince(pendingSeek.issuedAt) < 1.5,\n               abs(elapsedTime - pendingSeek.time) > 2.0 {\n                newPlaybackState.currentTime = pendingSeek.time\n            } else {\n                newPlaybackState.currentTime = elapsedTime\n                if let pendingSeek,\n                   abs(elapsedTime - pendingSeek.time) <= 2.0 || Date().timeIntervalSince(pendingSeek.issuedAt) >= 1.5 {\n                    self.pendingSeek = nil\n                }\n            }\n        } else if diff {''',
)

# Add Octave web controller to the same compiled source file, avoiding Xcode project churn.
p = Path('boringNotch/MediaControllers/NowPlayingController.swift')
s = p.read_text()
marker = '// MARK: - Octave Streaming web controller'
if marker not in s:
    s += r'''

// MARK: - Octave Streaming web controller
/// First-class controller for https://music.octavestreaming.com/. Transport remains on
/// MediaRemote, while browser-tab detection prevents unrelated web media from appearing
/// when Octave is explicitly selected.
final class OctaveStreamingController: ObservableObject, MediaControllerProtocol {
    static let syntheticBundleIdentifier = "com.boringnotch.octave.web"

    @Published private(set) var playbackState = PlaybackState(bundleIdentifier: syntheticBundleIdentifier)
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }

    private let base: NowPlayingController
    private var cancellable: AnyCancellable?
    private var detectionGeneration = 0

    init?() {
        guard let base = NowPlayingController() else { return nil }
        self.base = base
        cancellable = base.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.acceptIfOctaveIsOpen(state) }
    }

    private func acceptIfOctaveIsOpen(_ state: PlaybackState) {
        detectionGeneration &+= 1
        let generation = detectionGeneration
        Task { [weak self] in
            let detected = await OctaveBrowserDetector.shared.hasOctaveTab()
            guard let self, generation == self.detectionGeneration else { return }
            await MainActor.run {
                guard detected else {
                    var idle = PlaybackState(bundleIdentifier: Self.syntheticBundleIdentifier)
                    idle.isPlaying = false
                    self.playbackState = idle
                    return
                }
                var mapped = state
                mapped.bundleIdentifier = Self.syntheticBundleIdentifier
                self.playbackState = mapped
            }
        }
    }

    func setFavorite(_ favorite: Bool) async {}
    func play() async { await base.play() }
    func pause() async { await base.pause() }
    func seek(to time: Double) async { await base.seek(to: time) }
    func nextTrack() async { await base.nextTrack() }
    func previousTrack() async { await base.previousTrack() }
    func togglePlay() async { await base.togglePlay() }
    func toggleShuffle() async { await base.toggleShuffle() }
    func toggleRepeat() async { await base.toggleRepeat() }
    func setVolume(_ level: Double) async { await base.setVolume(level) }
    func isActive() -> Bool { true }
    func updatePlaybackInfo() async { await base.updatePlaybackInfo() }
}

private actor OctaveBrowserDetector {
    static let shared = OctaveBrowserDetector()
    private var cachedResult = false
    private var cachedAt = Date.distantPast

    func hasOctaveTab() async -> Bool {
        if Date().timeIntervalSince(cachedAt) < 0.75 { return cachedResult }

        let scripts = [
            Self.chromiumScript(appName: "Google Chrome"),
            Self.chromiumScript(appName: "Brave Browser"),
            Self.chromiumScript(appName: "Microsoft Edge"),
            Self.safariScript
        ]

        var found = false
        for script in scripts {
            if let descriptor = try? await AppleScriptHelper.execute(script), descriptor.booleanValue {
                found = true
                break
            }
        }
        cachedResult = found
        cachedAt = Date()
        return found
    }

    private static func chromiumScript(appName: String) -> String {
        """
        if application \"\(appName)\" is running then
            tell application \"\(appName)\"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (URL of t) starts with \"https://music.octavestreaming.com\" then return true
                        end try
                    end repeat
                end repeat
            end tell
        end if
        return false
        """
    }

    private static let safariScript = """
    if application \"Safari\" is running then
        tell application \"Safari\"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (URL of t) starts with \"https://music.octavestreaming.com\" then return true
                    end try
                end repeat
            end repeat
        end tell
    end if
    return false
    """
}
'''
    p.write_text(s)

# Octave-first lyric routing, followed by existing fallbacks.
replace_once(
    'boringNotch/managers/Lyrics/LyricFeverLyricsService.swift',
    '    private let spotifyProvider = LyricFeverSpotifyLyricProvider()\n',
    '    private let spotifyProvider = LyricFeverSpotifyLyricProvider()\n    private let octaveProvider = LyricFeverOctaveLyricProvider()\n',
)
replace_once(
    'boringNotch/managers/Lyrics/LyricFeverLyricsService.swift',
    '        var providers: [LyricFeverLyricProvider] = []\n\n        if bundleIdentifier == "com.spotify.client",',
    '        var providers: [LyricFeverLyricProvider] = []\n\n        if bundleIdentifier == OctaveStreamingController.syntheticBundleIdentifier {\n            providers.append(octaveProvider)\n        }\n\n        if bundleIdentifier == "com.spotify.client",',
)

p = Path('boringNotch/managers/Lyrics/LyricFeverLyricsService.swift')
s = p.read_text()
provider_marker = 'private final class LyricFeverOctaveLyricProvider'
if provider_marker not in s:
    insert_at = s.index('private final class LyricFeverLRCLIBLyricProvider')
    provider = r'''private final class LyricFeverOctaveLyricProvider: LyricFeverLyricProvider {
    let providerName = "Octave Lyric Provider"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func fetchNetworkLyrics(
        trackName: String,
        trackID: String,
        currentlyPlayingArtist: String?,
        currentAlbumName: String?
    ) async throws -> LyricFeverNetworkFetchReturn {
        var components = URLComponents(string: "https://music.octavestreaming.com/api/lyrics")!
        components.queryItems = [
            URLQueryItem(name: "title", value: trackName),
            URLQueryItem(name: "artist", value: currentlyPlayingArtist ?? ""),
            URLQueryItem(name: "album", value: currentAlbumName ?? "")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let lines = try Self.parse(data)
        return LyricFeverNetworkFetchReturn(lyrics: lines, colorData: nil)
    }

    private static func parse(_ data: Data) throws -> [LyricFeverLyricLine] {
        let json = try JSONSerialization.jsonObject(with: data)

        func lrcString(from value: Any) -> String? {
            if let string = value as? String { return string }
            guard let dictionary = value as? [String: Any] else { return nil }
            for key in ["syncedLyrics", "synced_lyrics", "lrc", "lyrics"] {
                if let found = dictionary[key] as? String { return found }
            }
            if let nested = dictionary["data"] { return lrcString(from: nested) }
            return nil
        }

        if let dictionary = json as? [String: Any],
           let array = (dictionary["lines"] ?? (dictionary["data"] as? [String: Any])?["lines"]) as? [[String: Any]] {
            let parsed = array.compactMap { item -> LyricFeverLyricLine? in
                let text = (item["words"] ?? item["text"] ?? item["line"]) as? String
                let rawTime = item["startTimeMs"] ?? item["startTime"] ?? item["time"]
                guard let text, let rawTime else { return nil }
                let milliseconds: Double
                if let n = rawTime as? NSNumber { milliseconds = n.doubleValue > 1000 ? n.doubleValue : n.doubleValue * 1000 }
                else if let s = rawTime as? String, let n = Double(s) { milliseconds = n > 1000 ? n : n * 1000 }
                else { return nil }
                return LyricFeverLyricLine(startTime: milliseconds, words: text)
            }
            if parsed.count > 1 { return parsed }
        }

        guard let lrc = lrcString(from: json) else { return [] }
        let regex = try NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)"#)
        return lrc.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 5,
                  let minRange = Range(match.range(at: 1), in: line),
                  let secRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 4), in: line),
                  let minutes = Double(line[minRange]), let seconds = Double(line[secRange]) else { return nil }
            var fraction = 0.0
            if match.range(at: 3).location != NSNotFound, let fracRange = Range(match.range(at: 3), in: line) {
                let digits = String(line[fracRange])
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return LyricFeverLyricLine(startTime: (minutes * 60 + seconds + fraction) * 1000, words: text)
        }
    }
}

'''
    p.write_text(s[:insert_at] + provider + s[insert_at:])

print('Octave integration applied successfully')
