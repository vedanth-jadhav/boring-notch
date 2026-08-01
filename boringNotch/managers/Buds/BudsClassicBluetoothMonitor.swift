import Foundation
import IOBluetooth

@MainActor
final class BudsClassicBluetoothMonitor: ObservableObject {
    static let shared = BudsClassicBluetoothMonitor()

    @Published private(set) var connectedDeviceName: String?

    private var refreshTask: Task<Void, Never>?
    private let targetNameFragments = ["oneplus", "nord buds"]

    private init() {
        start()
    }

    deinit {
        refreshTask?.cancel()
    }

    var isConnected: Bool {
        connectedDeviceName != nil
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        connectedDeviceName = devices.first(where: { device in
            guard device.isConnected(), let name = device.name else { return false }
            return isTargetBudsName(name)
        })?.name
    }

    private func isTargetBudsName(_ name: String) -> Bool {
        let normalized = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        return targetNameFragments.contains { normalized.contains($0) }
    }
}
