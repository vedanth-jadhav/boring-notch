//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import NaturalLanguage
import SwiftUI

#if canImport(Translation)
import Translation
#endif

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @Published var trackID: String? = nil
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    // MARK: - Unified lyric state (single @Published to reduce SwiftUI diff cascade)
    struct LyricState {
        var lines: [BoringLyricLine] = []
        var syncedLines: [(time: Double, text: String)] = []
        var plainText: String = ""
        var translated: [String] = []
        var isFetching: Bool = false
        var isFetchingTranslation: Bool = false
        var translationToken: UUID = UUID()
    }

    @Published var lyricState = LyricState()

    // Backward-compatible computed accessors — views reference these transparently
    var lyricLines: [BoringLyricLine] { lyricState.lines }
    var syncedLyrics: [(time: Double, text: String)] { lyricState.syncedLines }
    var currentLyrics: String { lyricState.plainText }
    var translatedLyrics: [String] { lyricState.translated }
    var isFetchingLyrics: Bool { lyricState.isFetching }
    var isFetchingTranslation: Bool { lyricState.isFetchingTranslation }
    var lyricTranslationToken: UUID { lyricState.translationToken }

    // Remove the old individual @Published declarations
    // @Published var currentLyrics: String = ""
    // @Published var isFetchingLyrics: Bool = false
    // @Published var syncedLyrics: [(time: Double, text: String)] = []
    // @Published var lyricLines: [BoringLyricLine] = []
    // @Published var translatedLyrics: [String] = []
    // @Published var isFetchingTranslation = false
    // @Published var lyricTranslationToken = UUID()
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil
    private var lyricFetchTask: Task<Void, Never>?
    private let lyricsService = LyricFeverLyricsService.shared
    private let romanizationService = LyricRomanizationService.shared

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        lyricFetchTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        case .octaveStreaming:
            newController = OctaveStreamingController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        let trackIDChanged = state.trackID != self.trackID

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let metadataChanged = titleChanged || artistChanged || albumChanged || bundleChanged || trackIDChanged
        let hasContentChange = metadataChanged || artworkChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            if artworkChanged || state.artwork == nil {
                // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if state.trackID != self.trackID {
            self.trackID = state.trackID
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated

        // Only metadata changes (not artwork-only) should trigger lyrics —
        // artwork arrives async after the first publish and would cancel the in-flight fetch.
        if metadataChanged {
            self.fetchLyricsIfAvailable(
                bundleIdentifier: state.bundleIdentifier,
                title: state.title,
                artist: state.artist,
                album: state.album,
                trackID: state.trackID
            )
        }
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String, album: String, trackID: String?) {
        fetchLyrics(
            title: title,
            artist: artist,
            album: album,
            trackID: trackID,
            bundleIdentifier: bundleIdentifier,
            force: false
        )
    }

    func refreshLyricsForCurrentTrack() {
        fetchLyrics(
            title: songTitle,
            artist: artistName,
            album: album,
            trackID: trackID,
            bundleIdentifier: bundleIdentifier,
            force: true
        )
    }

    private func fetchLyrics(title: String, artist: String, album: String, trackID: String?, bundleIdentifier: String?, force: Bool) {
        let shouldFetch = force || Defaults[.enableLyrics]
        guard shouldFetch, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetLyrics()
            return
        }

        let requestKey = "\(title)\u{1F}\(artist)\u{1F}\(album)\u{1F}\(trackID ?? "")\u{1F}\(bundleIdentifier ?? "")"
        lyricFetchTask?.cancel()
        lyricFetchTask = Task { [weak self] in
            // No debounce needed — lyricFetchTask.cancel() + requestKey guard handle rapid skips.
            await MainActor.run {
                self?.lyricState.isFetching = true
                self?.lyricState.plainText = ""
                self?.lyricState.lines = []
                self?.lyricState.translated = []
            }

            let duration = await MainActor.run { self?.songDuration ?? 0 }
            let lines = await self?.lyricsService.fetchLyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                trackID: trackID,
                bundleIdentifier: bundleIdentifier
            ) ?? []

            await MainActor.run {
                guard let self else { return }
                let currentKey = "\(self.songTitle)\u{1F}\(self.artistName)\u{1F}\(self.album)\u{1F}\(self.trackID ?? "")\u{1F}\(self.bundleIdentifier ?? "")"
                guard currentKey == requestKey, !Task.isCancelled else { return }
                self.setLyrics(lines)
            }
        }
    }

    private func resetLyrics() {
        lyricFetchTask?.cancel()
        lyricState = LyricState()
    }

    private func setLyrics(_ lines: [BoringLyricLine]) {
        let sorted = lines.sorted { $0.startTime < $1.startTime }

        // Pre-compute romanization once at load time instead of per-tick
        if Defaults[.enableLyricRomanization], sorted.contains(where: { romanizationService.containsIndicScript($0.words) }) {
            let romanized = sorted.map { line in
                BoringLyricLine(
                    startTime: line.startTime,
                    words: line.words,
                    romanizedWords: romanizationService.romanize(line.words)
                )
            }
            lyricState = LyricState(
                lines: romanized,
                syncedLines: romanized.map { ($0.startTime, $0.romanizedWords) },
                plainText: romanized.map(\.romanizedWords).joined(separator: "\n")
            )
        } else {
            lyricState = LyricState(
                lines: sorted,
                syncedLines: sorted.map { ($0.startTime, $0.words) },
                plainText: sorted.map(\.words).joined(separator: "\n")
            )
        }

        // Speculative preload: fire-and-forget the next track's lyrics at background priority.
        // fetchLyrics() has a fast cache check (<1μs), so if already cached this returns instantly.
        Task(priority: .background) { [weak self] in
            guard let self, let controller = self.activeController else { return }
            guard let next = await controller.peekNextTrack() else { return }
            _ = await self.lyricsService.fetchLyrics(
                title: next.title,
                artist: next.artist,
                album: next.album,
                duration: 0,
                trackID: self.trackID,
                bundleIdentifier: self.bundleIdentifier
            )
        }
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !lyricLines.isEmpty else { return currentLyrics }
        let index = currentLyricIndex(at: elapsed)
        if translatedLyrics.indices.contains(index), !translatedLyrics[index].isEmpty {
            return translatedLyrics[index]
        }
        return lyricLines[index].romanizedWords
    }

    func lyricDisplayContext(at elapsed: Double) -> LockScreenLyricDisplayContext {
        guard !lyricLines.isEmpty else {
            let text: String
            if isFetchingLyrics {
                text = "Loading translated lyrics..."
            } else {
                text = currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "No synced lyrics found"
                    : currentLyrics.replacing("\n", with: " ")
            }

            let current = LockScreenLyricDisplayLine(
                id: "fallback-\(text)",
                role: .current,
                originalText: text,
                translatedText: nil
            )
            return LockScreenLyricDisplayContext(previous: nil, current: current, upcoming: [], currentID: current.id)
        }

        let index = currentLyricIndex(at: elapsed)
        let previous = displayLine(index: index - 1, role: .previous)
        let current = displayLine(index: index, role: .current) ?? LockScreenLyricDisplayLine(
            id: "missing-current",
            role: .current,
            originalText: "No synced lyrics found",
            translatedText: nil
        )
        let upcoming = (1...2).compactMap { offset in
            displayLine(index: index + offset, role: .upcoming(offset))
        }

        return LockScreenLyricDisplayContext(
            previous: previous,
            current: current,
            upcoming: upcoming,
            currentID: current.id
        )
    }

    private func displayLine(index: Int, role: LockScreenLyricDisplayLine.Role) -> LockScreenLyricDisplayLine? {
        guard lyricLines.indices.contains(index) else { return nil }
        let lyric = lyricLines[index]
        return LockScreenLyricDisplayLine(
            id: "\(index)-\(lyric.id)",
            role: role,
            originalText: lyric.romanizedWords,
            translatedText: translatedLyrics.indices.contains(index) ? translatedLyrics[index] : nil
        )
    }

    private func currentLyricIndex(at elapsed: Double) -> Int {
        guard !lyricLines.isEmpty else { return 0 }

        var low = 0
        var high = lyricLines.count - 1
        var index = 0

        while low <= high {
            let mid = (low + high) / 2
            if lyricLines[mid].startTime <= elapsed {
                index = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return index
    }

    func detectLyricsLanguage() -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        let sample = lyricLines
            .prefix(12)
            .map(\.words)
            .joined(separator: "\n")

        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    func clearTranslatedLyrics() {
        lyricState.isFetchingTranslation = false
        lyricState.translated = []
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    func translateCurrentLyrics(using session: TranslationSession) async {
        guard !lyricLines.isEmpty else {
            clearTranslatedLyrics()
            return
        }

        lyricState.isFetchingTranslation = true
        let sourceIDs = lyricState.lines.map(\.id)
        let request = zip(sourceIDs, lyricState.lines).map { id, lyric in
            TranslationSession.Request(sourceText: lyric.words, clientIdentifier: id.uuidString)
        }

        do {
            let response = try await session.translations(from: request)
            guard sourceIDs == lyricState.lines.map(\.id) else { return }
            lyricState.translated = response.map(\.targetText)
            lyricState.isFetchingTranslation = false
        } catch {
            lyricState.isFetchingTranslation = false
        }
    }
    #endif

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        guard let controller = activeController else { return }
        isShuffled.toggle()

        Task(priority: .userInitiated) {
            await controller.toggleShuffle()
        }
    }

    func toggleRepeat() {
        guard let controller = activeController else { return }

        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }

        Task(priority: .userInitiated) {
            await controller.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func togglePlayReliably() {
        guard let controller = activeController else { return }

        let targetIsPlaying = !isPlaying
        withAnimation(.smooth(duration: 0.16)) {
            isPlaying = targetIsPlaying
            updateIdleState(state: targetIsPlaying)
        }

        Task(priority: .userInitiated) {
            if targetIsPlaying {
                await controller.play()
            } else {
                await controller.pause()
            }

            try? await Task.sleep(for: .milliseconds(80))
            await controller.updatePlaybackInfo()

            try? await Task.sleep(for: .milliseconds(180))
            let commandDidNotStick = await MainActor.run {
                self.isPlaying != targetIsPlaying
            }

            if commandDidNotStick {
                await controller.togglePlay()
            }
        }
    }

    func nextTrack() {
        guard let controller = activeController else { return }

        Task(priority: .userInitiated) {
            await controller.nextTrack()
            // Controllers that do not get reliable post-command push updates opt in to an explicit poll.
            if controller.requiresExplicitPolling {
                try? await Task.sleep(for: .milliseconds(120))
                await controller.updatePlaybackInfo()
            }
        }
    }

    func previousTrack() {
        guard let controller = activeController else { return }

        Task(priority: .userInitiated) {
            await controller.previousTrack()
            if controller.requiresExplicitPolling {
                try? await Task.sleep(for: .milliseconds(120))
                await controller.updatePlaybackInfo()
            }
        }
    }

    func seek(to position: TimeInterval) {
        guard let controller = activeController else { return }
        elapsedTime = position
        timestampDate = Date.now

        Task(priority: .userInitiated) {
            await controller.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
}
