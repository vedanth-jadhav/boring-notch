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

import AppKit
import Combine
import Defaults
import QuartzCore
import SkyLightWindow
import SwiftUI

@MainActor
final class LockScreenPanelAnimator: ObservableObject {
    @Published var isPresented = false
}

@MainActor
final class LockScreenMusicWindowManager {
    static let shared = LockScreenMusicWindowManager()

    private var panelWindow: NSWindow?
    private var hasDelegated = false
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var currentAdditionalWidth: CGFloat = 0
    private var currentAdditionalHeight: CGFloat = 0
    private var preferredScreenUUID: String?
    private let panelAnimator = LockScreenPanelAnimator()
    private let panelCornerRadius: CGFloat = 28
    private(set) var latestFrame: NSRect?

    private init() {
        registerScreenChangeObservers()
        observeDefaultChanges()
    }

    func show(screenUUID: String?) {
        preferredScreenUUID = screenUUID

        guard Defaults[.lockScreenMusicWidget] else {
            hide()
            return
        }

        guard let screen = preferredScreen(screenUUID: screenUUID) else { return }

        let panelSize = CGSize(
            width: LockScreenMusicWidgetView.collapsedSize.width + currentAdditionalWidth,
            height: LockScreenMusicWidgetView.collapsedSize.height + currentAdditionalHeight
        )
        let targetFrame = targetFrame(for: screen.frame, panelSize: panelSize)
        let window = ensureWindow(frame: targetFrame)

        window.setFrame(targetFrame, display: true)
        latestFrame = targetFrame
        hideTask?.cancel()
        panelAnimator.isPresented = false

        let hosting = NSHostingView(rootView: LockScreenMusicWidgetView(animator: panelAnimator))
        hosting.frame = NSRect(origin: .zero, size: targetFrame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.masksToBounds = true
            content.layer?.cornerRadius = panelCornerRadius
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        window.orderFrontRegardless()

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.panelAnimator.isPresented = true
        }
    }

    func updatePanelSize(additionalWidth: CGFloat = 0, additionalHeight: CGFloat = 0, animated: Bool = true) {
        currentAdditionalWidth = additionalWidth
        currentAdditionalHeight = additionalHeight

        guard let window = panelWindow, window.isVisible else { return }
        guard let screen = preferredScreen(screenUUID: preferredScreenUUID) else { return }

        let panelSize = CGSize(
            width: LockScreenMusicWidgetView.collapsedSize.width + additionalWidth,
            height: LockScreenMusicWidgetView.collapsedSize.height + additionalHeight
        )
        let targetFrame = targetFrame(for: screen.frame, panelSize: panelSize)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }

        latestFrame = targetFrame

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.28)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            window.contentView?.layer?.cornerRadius = panelCornerRadius
            CATransaction.commit()
        } else {
            window.contentView?.layer?.cornerRadius = panelCornerRadius
        }
    }

    func hide() {
        panelAnimator.isPresented = false
        hideTask?.cancel()

        guard let window = panelWindow else {
            latestFrame = nil
            return
        }

        hideTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(360))

            await MainActor.run {
                window?.orderOut(nil)
                window?.contentView = nil
                self?.latestFrame = nil
            }
        }
    }

    private func ensureWindow(frame: NSRect) -> NSWindow {
        if let panelWindow { return panelWindow }

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovable = false
        window.hasShadow = false
        window.animationBehavior = .none
        updateSharingType(for: window)

        panelWindow = window
        hasDelegated = false
        return window
    }

    private func targetFrame(for screenFrame: NSRect, panelSize: CGSize) -> NSRect {
        let originX = screenFrame.midX - (panelSize.width / 2)
        let baseOriginY = screenFrame.origin.y + (screenFrame.height / 2) - panelSize.height - 8

        return NSRect(
            x: originX,
            y: baseOriginY,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func preferredScreen(screenUUID: String?) -> NSScreen? {
        if let screenUUID, let screen = NSScreen.screen(withUUID: screenUUID) {
            return screen
        }

        if let builtin = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtin
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func registerScreenChangeObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange()
            }
        }
    }

    private func observeDefaultChanges() {
        Defaults.publisher(.lockScreenMusicPanelWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePanelSize(
                        additionalWidth: self?.currentAdditionalWidth ?? 0,
                        additionalHeight: self?.currentAdditionalHeight ?? 0
                    )
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenMusicWidget)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    if !change.newValue {
                        self?.hide()
                    } else if self?.panelWindow?.isVisible == true {
                        self?.updatePanelSize(
                            additionalWidth: self?.currentAdditionalWidth ?? 0,
                            additionalHeight: self?.currentAdditionalHeight ?? 0
                        )
                    }
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideFromScreenRecording)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let window = self?.panelWindow else { return }
                self?.updateSharingType(for: window)
            }
            .store(in: &cancellables)
    }

    private func handleScreenGeometryChange() {
        guard panelWindow?.isVisible == true else { return }
        updatePanelSize(additionalWidth: currentAdditionalWidth, additionalHeight: currentAdditionalHeight, animated: false)
    }

    private func updateSharingType(for window: NSWindow) {
        window.sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }
}
