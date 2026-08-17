//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        await refreshPlaybackState()
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
    }

    var requiresExplicitPolling: Bool { true }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier

        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        }

        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var pendingSeek: (time: Double, issuedAt: Date)?

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)

        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()

        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }

        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        let clamped = max(0, min(time, playbackState.duration > 0 ? playbackState.duration : time))
        pendingSeek = (clamped, Date())

        // Browser MediaSession seek handlers are asynchronous. Optimistically move the
        // local timeline and reconcile against the next authoritative MediaRemote sample.
        var updated = playbackState
        updated.currentTime = clamped
        updated.lastUpdated = Date()
        playbackState = updated

        MRMediaRemoteSetElapsedTimeFunction(clamped)
    }

    func isActive() -> Bool {
        return true
    }

    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }

    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }

    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)

        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == "com.apple.Music" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == "com.spotify.client" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }

        playbackState.volume = clampedLevel
    }

    private func refreshPlaybackState() async {
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            return
        }

        let payload = await Task.detached(priority: .utility) { () -> NowPlayingPayload? in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkPath, "get", "--now"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0, !data.isEmpty else { return nil }
                return try JSONDecoder().decode(NowPlayingPayload?.self, from: data)
            } catch {
                print("Failed to refresh MediaRemote playback state: \(error)")
                return nil
            }
        }.value

        guard let payload else { return }
        await handleAdapterUpdate(NowPlayingUpdate(payload: payload, diff: false))
    }

    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()

        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }

        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)

        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)

        if let elapsedTime = payload.elapsedTime {
            // A browser commonly emits one stale position sample immediately after a seek.
            // Keep the requested position briefly so the seek bar cannot snap backwards.
            if let pendingSeek,
               Date().timeIntervalSince(pendingSeek.issuedAt) < 1.5,
               abs(elapsedTime - pendingSeek.time) > 2.0 {
                newPlaybackState.currentTime = pendingSeek.time
            } else {
                newPlaybackState.currentTime = elapsedTime
                if let pendingSeek,
                   abs(elapsedTime - pendingSeek.time) <= 2.0 || Date().timeIntervalSince(pendingSeek.issuedAt) >= 1.5 {
                    self.pendingSeek = nil
                }
            }
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = self.playbackState.currentTime + (self.playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }


        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        if let dateString = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )

        newPlaybackState.volume = payload.volume ?? (diff ? self.playbackState.volume : 0.5)

        self.playbackState = newPlaybackState

        // Fetch favorite state for supported apps asynchronously
        // await fetchFavoriteStateIfSupported()
    }

     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier

         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }

             let script = """
             tell application "Music"
                 try
                     return favorited of current track
                 on error
                     return false
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 updated.isFavorite = result.booleanValue
                 self.playbackState = updated
             }
         }
     }

}

struct NowPlayingUpdate: Codable, Sendable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""

    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }

    func getPipe() -> Pipe {
        return pipe
    }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }

    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }

            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)

                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }

    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }

    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in

            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }

    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}


// MARK: - Octave Streaming web controller
/// First-class controller for https://music.octavestreaming.com/. Transport remains on
/// MediaRemote, while browser-tab detection prevents unrelated web media from appearing
/// when Octave is explicitly selected.
final class OctaveStreamingController: ObservableObject, MediaControllerProtocol, @unchecked Sendable {
    static let syntheticBundleIdentifier = "com.boringnotch.octave.web"

    @Published private(set) var playbackState = PlaybackState(bundleIdentifier: syntheticBundleIdentifier)
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }
    var requiresExplicitPolling: Bool { true }

    private let base: NowPlayingController
    private var cancellable: AnyCancellable?
    private var reconciliationTask: Task<Void, Never>?
    private var detectionGeneration = 0

    private static let supportedBrowserBundleIdentifiers = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac"
    ]

    private static let nativePlayerBundleIdentifiers: Set<String> = [
        "com.spotify.client",
        "com.apple.Music"
    ]

    private static func isSupportedBrowserBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        supportedBrowserBundleIdentifiers.contains { prefix in
            bundleIdentifier == prefix || bundleIdentifier.hasPrefix(prefix + ".")
        }
    }

    init?() {
        guard let base = NowPlayingController() else { return nil }
        self.base = base
        cancellable = base.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor [weak self] in self?.acceptIfOctaveIsOpen(state) }
            }

        // MediaRemote push updates are not authoritative for background browser tabs. Brave in
        // particular may keep emitting stale/no-op events, which defeated the old "only poll
        // when silent" reconciliation. Keep a cheap 1 Hz snapshot while Octave is selected so
        // metadata and transport state converge even when the tab is fully backgrounded.
        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            await self.base.updatePlaybackInfo()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.base.updatePlaybackInfo()
            }
        }
    }

    deinit {
        reconciliationTask?.cancel()
        cancellable?.cancel()
    }

    @MainActor
    private func acceptIfOctaveIsOpen(_ state: PlaybackState) {
        // Never reinterpret an explicitly identified native player as Octave merely because an
        // Octave tab is also open. Browser helper/PWA sessions, however, are deliberately not
        // rejected here: Chromium can report a helper or incomplete bundle identifier for a
        // background media session, so URL inspection must get the final say.
        if Self.nativePlayerBundleIdentifiers.contains(state.bundleIdentifier) {
            publishIdleState()
            return
        }

        detectionGeneration &+= 1
        let generation = detectionGeneration
        Task { [weak self] in
            let detection = await OctaveBrowserDetector.shared.detectOctaveTab(
                browserBundleIdentifier: state.bundleIdentifier
            )
            await MainActor.run {
                guard let self, generation == self.detectionGeneration else { return }

                switch detection {
                case .present:
                    var mapped = state
                    mapped.bundleIdentifier = Self.syntheticBundleIdentifier
                    self.playbackState = mapped

                case .absent:
                    self.publishIdleState()

                case .unavailable:
                    // If macOS has not granted browser automation yet, preserve usable browser
                    // metadata instead of making Octave disappear. This fallback is deliberately
                    // limited to a recognized browser family, so native players are never stolen.
                    if state.isPlaying || !state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              // `.unavailable` means at least one supported browser is running but every
              // attempted browser automation request failed. Chromium helper/PWA owners
              // need not use the browser's canonical MediaRemote bundle identifier.
                        var mapped = state
                        mapped.bundleIdentifier = Self.syntheticBundleIdentifier
                        self.playbackState = mapped
                    } else {
                        self.publishIdleState()
                    }
                }
            }
        }
    }

    @MainActor
    private func publishIdleState() {
        var idle = PlaybackState(bundleIdentifier: Self.syntheticBundleIdentifier)
        idle.isPlaying = false
        playbackState = idle
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
    enum DetectionResult: Sendable {
        case present
        case absent
        case unavailable
    }

    static let shared = OctaveBrowserDetector()
    private var cachedResult: DetectionResult = .absent
    private var cachedAt = Date.distantPast
    private var lastBrowserBundleIdentifier: String?
    private static let cacheInterval: TimeInterval = 0.75

    func detectOctaveTab(browserBundleIdentifier: String) async -> DetectionResult {
        let now = Date()
        if lastBrowserBundleIdentifier == browserBundleIdentifier,
           now.timeIntervalSince(cachedAt) < Self.cacheInterval {
            return cachedResult
        }

        let allCandidates: [(bundleIdentifier: String, script: String)] = [
            ("com.google.Chrome", Self.chromiumScript(appName: "Google Chrome")),
            ("com.brave.Browser", Self.chromiumScript(appName: "Brave Browser")),
            ("com.microsoft.edgemac", Self.chromiumScript(appName: "Microsoft Edge")),
            ("com.apple.Safari", Self.safariScript)
        ]

        // Prefer the browser MediaRemote names when it gives us a useful owner. If it reports a
        // helper/PWA/empty owner, inspect every running supported browser instead of rejecting the
        // session before URL detection gets a chance.
        let preferred = allCandidates.filter { candidate in
            browserBundleIdentifier == candidate.bundleIdentifier
                || browserBundleIdentifier.hasPrefix(candidate.bundleIdentifier + ".")
        }
        let candidates = preferred.isEmpty ? allCandidates : preferred

        var attempted = 0
        var failures = 0
        var result: DetectionResult = .absent

        for candidate in candidates {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).isEmpty else { continue }
            attempted += 1
            do {
                if let descriptor = try await AppleScriptHelper.execute(candidate.script), descriptor.booleanValue {
                    result = .present
                    break
                }
            } catch {
                failures += 1
                print("Octave browser detection AppleScript failed for \(candidate.bundleIdentifier): \(error)")
            }
        }

        if result != .present, attempted > 0, failures == attempted {
            result = .unavailable
        }

        cachedResult = result
        cachedAt = now
        lastBrowserBundleIdentifier = browserBundleIdentifier
        return result
    }

    private static func chromiumScript(appName: String) -> String {
        """
        if application \"\(appName)\" is running then
            tell application \"\(appName)\"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (URL of t) contains \"music.octavestreaming.com\" then return true
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
                        if (URL of t) contains \"music.octavestreaming.com\" then return true
                    end try
                end repeat
            end repeat
        end tell
    end if
    return false
    """
}
