//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }

    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async

    /// Optional — peek at the next track's metadata for speculative preloading.
    /// Returns nil when the next track is unknown or unsupported.
    func peekNextTrack() async -> (title: String, artist: String, album: String)?
}

extension MediaControllerProtocol {
    /// Default: no peek support.
    func peekNextTrack() async -> (title: String, artist: String, album: String)? { nil }
}
