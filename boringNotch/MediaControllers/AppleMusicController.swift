//
//  AppleMusicController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Music",
        playbackRate: 1
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool {
        return true
    }

    private var notificationTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.apple.Music.playerInfo")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
    }
    
    func pause() async {
        await executeCommand("pause")
    }
    
    func togglePlay() async {
        await executeCommand("playpause")
    }
    
    func nextTrack() async {
        await executeCommand("next track")
    }
    
    func previousTrack() async {
        await executeCommand("previous track")
    }
    
    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func setFavorite(_ favorite: Bool) async {
        let script = """
        tell application \"Music\"
            try
                set favorited of current track to " + (favorite ? "true" : "false") + "
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 10 else { return }
        var updatedState = self.playbackState

        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0
        updatedState.isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        updatedState.repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        updatedState.volume = Double(volumePercentage) / 100.0
        let lovedState = descriptor.atIndex(10)?.booleanValue ?? false
        updatedState.isFavorite = lovedState
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState

        // Fetch artwork separately after publishing metadata — avoids serializing
        // large binary data through the main AppleScript IPC.
        let trackChanged = updatedState.title != self._lastArtworkTitle || updatedState.artist != self._lastArtworkArtist
        if trackChanged {
            self._lastArtworkTitle = updatedState.title
            self._lastArtworkArtist = updatedState.artist
            Task(priority: .background) { [weak self] in
                guard let artworkData = await self?.fetchArtworkAsync() else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var withArtwork = self.playbackState
                    withArtwork.artwork = artworkData
                    self.playbackState = withArtwork
                }
            }
        }
    }

    // Track last known artwork identifiers for change detection
    private var _lastArtworkTitle: String = ""
    private var _lastArtworkArtist: String = ""
    
    // MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Music\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }
    
    /// Peek at the next track in the queue for speculative preloading.
    func peekNextTrack() async -> (title: String, artist: String, album: String)? {
        let script = """
        tell application "Music"
            try
                set nextTrackName to name of next track
                set nextTrackArtist to artist of next track
                set nextTrackAlbum to album of next track
                return {nextTrackName, nextTrackArtist, nextTrackAlbum}
            on error
                return {"", "", ""}
            end try
        end tell
        """
        guard let descriptor = try? await AppleScriptHelper.execute(script),
              descriptor.numberOfItems >= 3,
              let title = descriptor.atIndex(1)?.stringValue, !title.isEmpty,
              let artist = descriptor.atIndex(2)?.stringValue
        else { return nil }
        let album = descriptor.atIndex(3)?.stringValue ?? ""
        return (title, artist, album)
    }

    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                else if repeatState is all then
                    set repeatValue to 3
                end if

                set currentVolume to sound volume
                set favoriteState to favorited of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, currentVolume, favoriteState}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, 50, false}
            end try
        end tell
        """

        return try await AppleScriptHelper.execute(script)
    }

    /// Lightweight AppleScript to fetch only artwork data — avoids serializing
    /// large binary blobs through the main metadata AppleScript IPC.
    private func fetchArtworkAsync() async -> Data? {
        let script = """
        tell application "Music"
            try
                set artData to data of artwork 1 of current track
                return artData
            on error
                return ""
            end try
        end tell
        """
        guard let descriptor = try? await AppleScriptHelper.execute(script) else { return nil }
        return descriptor.data as Data?
    }
    
}
