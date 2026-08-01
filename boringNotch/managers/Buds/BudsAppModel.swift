import AppKit
import Combine
import SwiftUI

@MainActor
final class BudsAppModel: ObservableObject {
    static let shared = BudsAppModel()

    private let client: BudsClient
    private let classicMonitor = BudsClassicBluetoothMonitor.shared
    private var eventTask: Task<Void, Never>?
    private var classicCancellable: AnyCancellable?
    private var lastOnOpenBatteryQueryAt: Date?
    private var lastOnOpenANCQueryAt: Date?
    private var viewIsVisible = false
    private var visibilityCloseTask: Task<Void, Never>?

    @Published var connection: ConnectionState = .idle
    @Published var anc: ANCMode?
    @Published var battery: BatteryStatus?
    @Published var lastOperation: OperationEvent?
    @Published var lastError: String?
    @Published private(set) var classicConnectedDeviceName: String?

    private static let lowBatteryThreshold = 20
    private static let caseCachePercentKey = "boringNotch.buds.caseBatteryPercent"
    private static let caseCacheTimestampKey = "boringNotch.buds.caseBatteryTimestamp"
    private static let caseCacheMaxAge: TimeInterval = 12 * 60 * 60

    private convenience init() {
        self.init(client: BudsClientImpl())
    }

    private init(client: BudsClient) {
        self.client = client
        client.start()
        classicConnectedDeviceName = classicMonitor.connectedDeviceName

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in client.events {
                self.handle(event)
            }
        }

        classicCancellable = classicMonitor.$connectedDeviceName
            .receive(on: RunLoop.main)
            .sink { [weak self] name in
                self?.classicConnectedDeviceName = name
            }
    }

    deinit {
        eventTask?.cancel()
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    var shouldShowTab: Bool {
        isConnected || classicConnectedDeviceName != nil || isConnectingToBuds
    }

    var connectedDeviceName: String {
        if case .connected(let name) = connection, let name, !name.isEmpty {
            return name
        }
        if let classicConnectedDeviceName, !classicConnectedDeviceName.isEmpty {
            return classicConnectedDeviceName
        }
        return "Buds"
    }

    var connectionSubtitle: String {
        switch connection {
        case .connected:
            return "Controls ready"
        case .connecting, .discovering, .authenticating:
            return "Syncing controls"
        case .scanning where classicConnectedDeviceName != nil:
            return "Audio connected, finding controls"
        case .bluetoothUnauthorized:
            return "Bluetooth permission needed"
        case .bluetoothOff:
            return "Bluetooth is off"
        case .failed(let message):
            return message
        default:
            return classicConnectedDeviceName == nil ? "Looking for Buds" : "Audio connected"
        }
    }

    var displayBattery: BatteryStatus? {
        guard let battery else { return nil }
        if battery.case != nil { return battery }
        guard let cached = cachedCasePercent, let timestamp = cachedCaseTimestamp else { return battery }
        guard Date().timeIntervalSince(timestamp) <= Self.caseCacheMaxAge else { return battery }
        return BatteryStatus(left: battery.left, right: battery.right, case: cached, lastUpdated: battery.lastUpdated)
    }

    var totalBatteryText: String {
        guard let total = displayBattery?.totalWeightedPercent else { return "--" }
        return "\(total)%"
    }

    var batteryIsLow: Bool {
        guard let total = displayBattery?.totalWeightedPercent else { return false }
        return total < Self.lowBatteryThreshold
    }

    var ancLabel: String {
        switch anc {
        case .on: return "Noise Cancellation"
        case .transparency: return "Transparency"
        case .off: return "Off"
        case nil: return "Noise Control"
        }
    }

    func onViewAppear() {
        viewIsVisible = true
        visibilityCloseTask?.cancel()
        visibilityCloseTask = nil
        client.setLiveUpdatesEnabled(true)

        guard isConnected else { return }

        let now = Date()
        let batteryFresh = battery.map { now.timeIntervalSince($0.lastUpdated) < 5 * 60 } ?? false
        let canQueryBattery = lastOnOpenBatteryQueryAt.map { now.timeIntervalSince($0) > 20 } ?? true
        let canQueryANC = lastOnOpenANCQueryAt.map { now.timeIntervalSince($0) > 20 } ?? true

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard self.viewIsVisible, self.isConnected else { return }

            if !batteryFresh, canQueryBattery {
                self.lastOnOpenBatteryQueryAt = Date()
                self.client.queryBattery(source: .onOpen)
            }

            if self.anc == nil, canQueryANC {
                self.lastOnOpenANCQueryAt = Date()
                self.client.queryANC(source: .onOpen)
            }
        }
    }

    func onViewDisappear() {
        viewIsVisible = false
        visibilityCloseTask?.cancel()
        visibilityCloseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !self.viewIsVisible else { return }
            self.client.setLiveUpdatesEnabled(false)
        }
    }

    func setANC(_ mode: ANCMode) {
        lastError = nil
        client.setANC(mode)
    }

    func refreshBattery() {
        lastError = nil
        client.queryBattery(source: .user)
    }

    func reconnect() {
        lastError = nil
        classicMonitor.refresh()
        client.reconnectNow()
    }

    func refreshClassicConnection() {
        classicMonitor.refresh()
        classicConnectedDeviceName = classicMonitor.connectedDeviceName
    }

    private var isConnectingToBuds: Bool {
        switch connection {
        case .connecting, .discovering, .authenticating, .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    private var cachedCasePercent: Int? {
        UserDefaults.standard.object(forKey: Self.caseCachePercentKey) as? Int
    }

    private var cachedCaseTimestamp: Date? {
        UserDefaults.standard.object(forKey: Self.caseCacheTimestampKey) as? Date
    }

    private func updateCaseCacheIfNeeded(_ battery: BatteryStatus) {
        guard let casePercent = battery.case else { return }
        UserDefaults.standard.set(casePercent, forKey: Self.caseCachePercentKey)
        UserDefaults.standard.set(Date(), forKey: Self.caseCacheTimestampKey)
    }

    private func handle(_ event: BudsEvent) {
        switch event {
        case .connection(let state):
            connection = state
            if case .connected = state {
                lastError = nil
            }

            switch state {
            case .idle, .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnsupported, .bluetoothResetting, .scanning, .failed:
                anc = nil
            default:
                break
            }

            switch state {
            case .bluetoothOff:
                lastError = "Bluetooth is off"
            case .bluetoothUnauthorized:
                lastError = "Bluetooth permission needed"
            case .bluetoothUnsupported:
                lastError = "Bluetooth unsupported"
            case .failed(let message):
                lastError = message
            default:
                break
            }

        case .anc(let mode, _):
            anc = mode

        case .battery(let status, _):
            battery = status
            updateCaseCacheIfNeeded(status)

        case .operation(let operation):
            lastOperation = operation
            if case .failed(let message) = operation.phase {
                lastError = message
            }

        case .error(let error):
            lastError = error.message

        case .deviceInfo, .eq:
            break
        }
    }
}
