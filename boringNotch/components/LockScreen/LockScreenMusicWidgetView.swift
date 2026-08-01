/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Adapted for boring.notch lock-screen media controls.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import SwiftUI

struct LockScreenMusicWidgetView: View {
    static let collapsedHeight: CGFloat = 180
    static var collapsedSize: CGSize {
        CGSize(width: CGFloat(Defaults[.lockScreenMusicPanelWidth]), height: collapsedHeight)
    }

    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var animator: LockScreenPanelAnimator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lockScreenCaffeine) private var lockScreenCaffeine
    @Default(.lockScreenMusicLiquidGlassVariant) private var musicGlassVariant
    @Default(.lockScreenMusicPanelWidth) private var panelWidth
    @Default(.lockScreenPanelShowsBorder) private var showPanelBorder
    @Default(.lockScreenMusicUsesEnhancedLiquidBorder) private var useEnhancedLiquidBorder
    @State private var sliderValue: Double = 0
    @State private var dragging = false
    @State private var lastDragged = Date.distantPast
    @State private var isCoverExpanded = false
    @State private var isBetterLyricsVisible = false

    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }

    var body: some View {
        Group {
            if hasMusicContent {
                panelLayout
                    .frame(width: currentSize.width, height: currentSize.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                    .overlay {
                        if showPanelBorder && !isBetterLyricsVisible {
                            panelBorderOverlay
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
                    .opacity(animator.isPresented ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.8), value: animator.isPresented)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: isCoverExpanded)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: isBetterLyricsVisible)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: enableLyrics)
                    .onAppear {
                        sliderValue = musicManager.estimatedPlaybackPosition()
                        updatePanelSize(animated: false)
                    }
                    .onChange(of: enableLyrics) { _, _ in updatePanelSize() }
                    .onChange(of: panelWidth) { _, _ in updatePanelSize() }
                    .onChange(of: isCoverExpanded) { _, _ in updatePanelSize() }
                    .onChange(of: isBetterLyricsVisible) { _, visible in
                        if visible { musicManager.refreshLyricsForCurrentTrack() }
                        updatePanelSize()
                    }
            } else {
                Color.clear
                    .frame(width: currentSize.width, height: currentSize.height)
            }
        }
        .foregroundStyle(.white)
        .background {
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                LockScreenLyricsTranslationBridge(musicManager: musicManager)
            }
            #endif
        }
    }

    /// Static layout (background, album art, controls) — unchanged by timeline ticks.
    /// Only the progress bar and lyrics sections live inside a dedicated TimelineView.
    @ViewBuilder
    private var panelLayout: some View {
        if isBetterLyricsVisible {
            lyricsSplitLayout
        } else {
            ZStack(alignment: .topLeading) {
                LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: panelCornerRadius) {
                    Color.white.opacity(0.04)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if isCoverExpanded {
                    expandedCoverLayout
                } else {
                    compactLayout
                }
            }
        }
    }

    /// Compact mode: static header, controls, backgrounds — only progress and lyrics tick.
    private var compactLayout: some View {
        VStack(spacing: 12) {
            compactHeader
            timedProgress
                .padding(.top, 4)
            controlsRow
                .padding(.top, 4)

            if enableLyrics {
                timedInlineLyrics
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Expanded mode: static header + controls separately, only progress and lyrics tick.
    private var expandedCoverLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            albumArtButton(size: 156, cornerRadius: 28)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(2)

                        Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                            .font(.subheadline)
                            .foregroundStyle(brandAccentColor)
                            .lineLimit(1)

                        if !musicManager.album.isEmpty {
                            Text(musicManager.album)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.56))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                    headerActions
                }

                timedProgress
                controlsRow

                if enableLyrics {
                    timedInlineLyrics
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Split (better lyrics) mode: left static panel + right timed lyrics board.
    private var lyricsSplitLayout: some View {
        HStack(alignment: .top, spacing: splitGap) {
            ZStack(alignment: .topLeading) {
                LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: panelCornerRadius) {
                    Color.white.opacity(0.04)
                }
                .allowsHitTesting(false)

                if isCoverExpanded {
                    expandedCoverLayout
                        .padding(18)
                } else {
                    compactLayout
                }
            }
            .frame(width: leftPanelWidth, height: currentHeight, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
            .overlay {
                if showPanelBorder {
                    panelBorderOverlay
                }
            }

            timedLyricsBoard
                .frame(width: lyricsPanelWidth, height: currentHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Minimal TimelineView — only the progress bar ticks here.
    /// Header, controls, and backgrounds sit outside the TimelineView and stay static between ticks.
    private var timedProgress: some View {
        TimelineView(.animation(minimumInterval: timelineInterval)) { timeline in
            let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
            progressBar(elapsed: elapsed, currentDate: timeline.date)
        }
    }

    /// Separate lightweight TimelineView for inline lyrics (only shown when lyrics are enabled).
    private var timedInlineLyrics: some View {
        TimelineView(.animation(minimumInterval: timelineInterval)) { timeline in
            let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
            inlineLyricsSection(elapsed: elapsed)
        }
    }

    /// Separate TimelineView for the better-lyrics board (needs higher refresh rate).
    private var timedLyricsBoard: some View {
        TimelineView(.animation(minimumInterval: isBetterLyricsVisible ? 0.08 : 1.0)) { timeline in
            let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
            betterLyricsBoard(elapsed: elapsed)
        }
    }

    private var hasMusicContent: Bool {
        !musicManager.isPlayerIdle || musicManager.isPlaying || musicManager.songDuration > 0
    }

    private var currentSize: CGSize {
        CGSize(width: baseWidth + additionalWidth, height: currentHeight)
    }

    private var baseWidth: CGFloat {
        CGFloat(panelWidth)
    }

    private var additionalWidth: CGFloat {
        if isBetterLyricsVisible {
            return splitGap + lyricsPanelWidth + (isCoverExpanded ? 130 : 0)
        }

        if isCoverExpanded { return 130 }
        return 0
    }

    private var currentHeight: CGFloat {
        if isBetterLyricsVisible {
            return isCoverExpanded ? splitExpandedHeight : splitCollapsedHeight
        }

        if isCoverExpanded { return 326 }
        return Self.collapsedHeight + (enableLyrics ? 52 : 0)
    }

    private var leftPanelWidth: CGFloat {
        baseWidth + (isCoverExpanded ? 130 : 0)
    }

    private var lyricsPanelWidth: CGFloat {
        390
    }

    private var splitGap: CGFloat {
        16
    }

    private var splitCollapsedHeight: CGFloat {
        226
    }

    private var splitExpandedHeight: CGFloat {
        274
    }

    private var additionalHeight: CGFloat {
        max(0, currentHeight - Self.collapsedHeight)
    }

    private var timelineInterval: TimeInterval {
        guard musicManager.isPlaying else { return 1.0 }
        return isBetterLyricsVisible ? 0.08 : 0.2
    }

    private var dedicatedLyricsLeadTime: TimeInterval {
        0.22
    }

    private var panelCornerRadius: CGFloat {
        28
    }

    private var brandAccentColor: Color {
        Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.72)
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            albumArtButton(size: 60, cornerRadius: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                    .font(.system(size: 10))
                    .foregroundStyle(brandAccentColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            headerActions
            visualizer
        }
        .frame(height: 60)
    }

    private var headerActions: some View {
        HStack(spacing: 4) {
            headerButton(
                label: isBetterLyricsVisible ? "Hide Better Lyrics" : "Show Better Lyrics",
                icon: "text.quote",
                isActive: isBetterLyricsVisible,
                action: toggleBetterLyrics
            )

            headerButton(
                label: lockScreenCaffeine ? "Stop Caffeinating" : "Caffeinate Lock Screen",
                icon: lockScreenCaffeine ? "cup.and.saucer.fill" : "cup.and.saucer",
                isActive: lockScreenCaffeine,
                action: toggleCaffeine
            )
        }
    }

    private func headerButton(label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        LockScreenPanelControlButton(
            label: label,
            icon: icon,
            frameSize: 30,
            iconSize: 13,
            iconColor: isActive ? brandAccentColor : .white.opacity(0.76),
            backgroundOpacity: isActive ? 0.22 : 0.06,
            interaction: .none,
            symbolEffect: .replace,
            action: action
        )
    }

    private func albumArtButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                isCoverExpanded.toggle()
            }
        } label: {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .background {
                    LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: cornerRadius) {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: isCoverExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: max(10, size * 0.09), weight: .semibold))
                        .padding(6)
                        .background(.black.opacity(0.28), in: Circle())
                        .padding(6)
                        .opacity(size > 80 ? 0.88 : 0)
                }
                .opacity(musicManager.isPlaying ? 1 : 0.48)
                .scaleEffect(musicManager.isPlaying ? 1 : 0.9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCoverExpanded ? "Collapse album artwork" : "Expand album artwork")
    }

    @ViewBuilder
    private var visualizer: some View {
        Rectangle()
            .fill(Defaults[.coloredSpectrogram] ? brandAccentColor.gradient : Color.gray.gradient)
            .mask {
                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                    .frame(width: 20, height: 16)
            }
            .frame(width: 20, height: 16)
            .accessibilityHidden(true)
    }

    private func progressBar(elapsed: TimeInterval, currentDate: Date) -> some View {
        HStack(spacing: 12) {
            Text(timeText(elapsed))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            LockScreenInlineSlider(
                value: $sliderValue,
                range: 0...max(musicManager.songDuration, 0.1),
                color: sliderColor,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: MusicManager.shared.seek(to:)
            )
            .frame(height: 16)
            .onChange(of: currentDate) { _, _ in
                guard !dragging, Date.now.timeIntervalSince(lastDragged) > 0.5 else { return }
                sliderValue = elapsed
            }

            Text("-\(timeText(max(0, musicManager.songDuration - elapsed)))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var sliderColor: Color {
        switch Defaults[.sliderColor] {
        case .white:
            .white
        case .albumArt:
            brandAccentColor
        case .accent:
            .effectiveAccent
        }
    }

    private var controlsRow: some View {
        HStack(spacing: isBetterLyricsVisible ? 14 : 20) {
            controlButton(
                label: "Shuffle",
                icon: "shuffle",
                isActive: musicManager.isShuffled,
                action: MusicManager.shared.toggleShuffle
            )

            controlButton(
                label: "Previous Track",
                icon: "backward.fill",
                interaction: .nudge(-9),
                action: MusicManager.shared.previousTrack
            )

            controlButton(
                label: musicManager.isPlaying ? "Pause" : "Play",
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                frameSize: 54,
                iconSize: 28,
                symbolEffect: .replaceAndBounce,
                action: MusicManager.shared.togglePlayReliably
            )

            controlButton(
                label: "Next Track",
                icon: "forward.fill",
                interaction: .nudge(9),
                action: MusicManager.shared.nextTrack
            )

            controlButton(
                label: "Repeat",
                icon: repeatIcon,
                isActive: musicManager.repeatMode != .off,
                action: MusicManager.shared.toggleRepeat
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func controlButton(
        label: String,
        icon: String,
        frameSize: CGFloat = 32,
        iconSize: CGFloat = 18,
        isActive: Bool = false,
        interaction: LockScreenPanelControlButton.Interaction = .none,
        symbolEffect: LockScreenPanelControlButton.SymbolEffectStyle = .replace,
        action: @escaping () -> Void
    ) -> some View {
        LockScreenPanelControlButton(
            label: label,
            icon: icon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: isActive ? brandAccentColor : .white.opacity(0.8),
            backgroundOpacity: isActive ? 0.22 : 0,
            interaction: interaction,
            symbolEffect: symbolEffect,
            action: action
        )
    }

    private func inlineLyricsSection(elapsed: TimeInterval) -> some View {
        let line = lyricLine(elapsed: elapsed)

        return HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            Text(line)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: line)
    }

    private func betterLyricsBoard(elapsed: TimeInterval) -> some View {
        let context = musicManager.lyricDisplayContext(at: elapsed + dedicatedLyricsLeadTime)
        let lines = context.displayLines

        return ZStack(alignment: .topLeading) {
            LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: 24) {
                Color.white.opacity(0.035)
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                if musicManager.isFetchingLyrics || musicManager.isFetchingTranslation {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .tint(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        LockScreenLyricLineView(line: line)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: context.currentID)
    }

    private func lyricLine(elapsed: TimeInterval) -> String {
        if musicManager.isFetchingLyrics { return "Loading lyrics..." }
        if !musicManager.lyricLines.isEmpty {
            return musicManager.lyricLine(at: elapsed)
        }

        let lyrics = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        return lyrics.isEmpty ? "No lyrics found" : lyrics.replacing("\n", with: " ")
    }

    private var panelBorderOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(useEnhancedLiquidBorder ? 0.22 : 0.15), lineWidth: 1)

            if useEnhancedLiquidBorder {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.1),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            "repeat"
        case .all:
            "repeat"
        case .one:
            "repeat.1"
        }
    }

    private func toggleBetterLyrics() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            isBetterLyricsVisible.toggle()
        }
    }

    private func toggleCaffeine() {
        lockScreenCaffeine.toggle()
        CaffeineManager.shared.setActive(lockScreenCaffeine)
    }

    private func updatePanelSize(animated: Bool = true) {
        LockScreenMusicWindowManager.shared.updatePanelSize(
            additionalWidth: additionalWidth,
            additionalHeight: additionalHeight,
            animated: animated
        )
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(remainingSeconds))"
        }

        return "\(minutes):\(twoDigits(remainingSeconds))"
    }

    private func twoDigits(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}

private struct LockScreenInlineSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let onValueChange: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let rangeSpan = max(range.upperBound - range.lowerBound, 0.1)
            let progress = min(max((value - range.lowerBound) / rangeSpan, 0), 1)
            let trackHeight: CGFloat = dragging ? 11 : 7

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(color)
                    .frame(width: CGFloat(progress) * width, height: trackHeight)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation(.smooth(duration: 0.18)) {
                            dragging = true
                        }

                        let clampedX = min(max(gesture.location.x, 0), width)
                        let newValue = range.lowerBound + (Double(clampedX / width) * rangeSpan)
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange(value)
                        dragging = false
                        lastDragged = Date.now
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
