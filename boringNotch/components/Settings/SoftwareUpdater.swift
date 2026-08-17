//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import AppKit
import CryptoKit
import Sparkle
import SwiftUI

private struct BoringNotchUpdateManifest: Decodable, Sendable {
    let version: String
    let build: String
    let dmgURL: URL
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case dmgURL = "dmg_url"
        case sha256
    }
}

/// Fork-owned updater used by the beta builds. Sparkle remains linked for compatibility with
/// upstream, but these builds cannot use the upstream EdDSA key. This updater checks a small
/// manifest published next to the mutable `beta` release, verifies the DMG against GitHub's
/// published SHA-256, then asks the unsandboxed XPC helper to replace and relaunch the app.
@MainActor
final class ForkReleaseUpdater: ObservableObject {
    static let shared = ForkReleaseUpdater()

    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var availableVersion: String?

    @Published var automaticallyChecksForUpdates: Bool {
        didSet { defaults.set(automaticallyChecksForUpdates, forKey: Self.autoCheckKey) }
    }

    @Published var automaticallyInstallsUpdates: Bool {
        didSet { defaults.set(automaticallyInstallsUpdates, forKey: Self.autoInstallKey) }
    }

    private static let autoCheckKey = "BoringNotchForkAutomaticallyChecksForUpdates"
    private static let autoInstallKey = "BoringNotchForkAutomaticallyInstallsUpdates"
    private static let checkInterval: Duration = .seconds(6 * 60 * 60)
    private static let manifestURL = URL(
        string: "https://github.com/vedanth-jadhav/boring-notch/releases/download/beta/latest.json"
    )!

    private let defaults: UserDefaults
    private var scheduledCheckTask: Task<Void, Never>?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyChecksForUpdates = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
        automaticallyInstallsUpdates = defaults.object(forKey: Self.autoInstallKey) as? Bool ?? true
    }

    func start() {
        guard scheduledCheckTask == nil else { return }

        scheduledCheckTask = Task { [weak self] in
            // Do not compete with launch/onboarding work, but make the first check quick enough
            // that a broken build does not linger for a day.
            try? await Task.sleep(for: .seconds(5))

            while !Task.isCancelled {
                guard let self else { return }
                if self.automaticallyChecksForUpdates {
                    await self.performCheck(userInitiated: false)
                }

                do {
                    try await Task.sleep(for: Self.checkInterval)
                } catch {
                    return
                }
            }
        }
    }

    func checkForUpdates() {
        Task { [weak self] in
            await self?.performCheck(userInitiated: true)
        }
    }

    private func performCheck(userInitiated: Bool) async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.manifestURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("boring-notch-macos", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidManifestResponse
            }

            let manifest = try JSONDecoder().decode(BoringNotchUpdateManifest.self, from: data)
            guard let remoteBuild = Int64(manifest.build), remoteBuild > 0 else {
                throw UpdateError.invalidBuildNumber
            }

            let currentBuildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            let currentBuild = Int64(currentBuildString) ?? 0
            availableVersion = remoteBuild > currentBuild ? manifest.version : nil

            guard remoteBuild > currentBuild else {
                if userInitiated {
                    presentInformation(
                        title: "Boring Notch is up to date",
                        message: "You are running the newest beta build (\(currentBuildString))."
                    )
                }
                return
            }

            if automaticallyInstallsUpdates && !userInitiated {
                await downloadAndInstall(manifest, userInitiated: false)
                return
            }

            let shouldInstall = presentConfirmation(
                title: "Boring Notch \(manifest.version) is available",
                message: "Build \(manifest.build) is ready. Install it now?",
                confirmTitle: "Install Update",
                cancelTitle: "Later"
            )
            if shouldInstall {
                await downloadAndInstall(manifest, userInitiated: userInitiated)
            }
        } catch {
            if userInitiated {
                presentInformation(
                    title: "Couldn’t check for updates",
                    message: error.localizedDescription
                )
            } else {
                NSLog("Boring Notch update check failed: %@", error.localizedDescription)
            }
        }
    }

    private func downloadAndInstall(_ manifest: BoringNotchUpdateManifest, userInitiated: Bool) async {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        do {
            var request = URLRequest(url: manifest.dmgURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 120
            request.setValue("boring-notch-macos", forHTTPHeaderField: "User-Agent")

            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.downloadFailed
            }

            let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BoringNotchUpdates", isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let localDMG = cacheDirectory.appendingPathComponent("Boring-Notch-Beta-\(manifest.build).dmg")
            try? FileManager.default.removeItem(at: localDMG)
            try FileManager.default.copyItem(at: temporaryURL, to: localDMG)

            let actualDigest = try await sha256(of: localDMG)
            guard actualDigest.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
                try? FileManager.default.removeItem(at: localDMG)
                throw UpdateError.checksumMismatch
            }

            let prepared = await XPCHelperClient.shared.prepareUpdateInstallation(
                dmgPath: localDMG.path,
                currentAppPath: Bundle.main.bundlePath,
                hostPID: Int32(ProcessInfo.processInfo.processIdentifier)
            )

            if prepared {
                NSApplication.shared.terminate(nil)
                return
            }

            // A read-only/translocated app location cannot be replaced in place. The verified
            // DMG still gives the user a deterministic recovery path instead of a dead button.
            NSWorkspace.shared.open(localDMG)
            presentInformation(
                title: "Update downloaded",
                message: "The current app location can’t be replaced automatically, so the verified DMG was opened. Move Boring Notch to Applications to enable one-click updates."
            )
        } catch {
            if userInitiated {
                presentInformation(title: "Update failed", message: error.localizedDescription)
            } else {
                NSLog("Boring Notch automatic update failed: %@", error.localizedDescription)
            }
        }
    }

    private func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private func presentConfirmation(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentInformation(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private enum UpdateError: LocalizedError {
        case invalidManifestResponse
        case invalidBuildNumber
        case downloadFailed
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidManifestResponse:
                return "The beta update manifest could not be loaded from GitHub."
            case .invalidBuildNumber:
                return "The beta update manifest contains an invalid build number."
            case .downloadFailed:
                return "The beta DMG could not be downloaded from GitHub."
            case .checksumMismatch:
                return "The downloaded DMG failed SHA-256 verification and was discarded."
            }
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var releaseUpdater = ForkReleaseUpdater.shared

    init(updater: SPUUpdater) {
        // Keep the existing call sites/source compatibility. Fork beta updates are handled by
        // ForkReleaseUpdater because the upstream Sparkle signing key cannot sign this fork.
        _ = updater
    }

    var body: some View {
        Button(releaseUpdater.isChecking ? "Checking for Updates…" : "Check for Updates…") {
            releaseUpdater.checkForUpdates()
        }
        .disabled(releaseUpdater.isChecking || releaseUpdater.isInstalling)
    }
}

struct UpdaterSettingsView: View {
    @ObservedObject private var releaseUpdater = ForkReleaseUpdater.shared

    init(updater: SPUUpdater) {
        _ = updater
    }

    var body: some View {
        Section {
            Toggle(
                "Automatically check for updates",
                isOn: $releaseUpdater.automaticallyChecksForUpdates
            )

            Toggle(
                "Automatically download and install updates",
                isOn: $releaseUpdater.automaticallyInstallsUpdates
            )
            .disabled(!releaseUpdater.automaticallyChecksForUpdates)
        } header: {
            HStack {
                Text("Software updates")
            }
        }
    }
}
