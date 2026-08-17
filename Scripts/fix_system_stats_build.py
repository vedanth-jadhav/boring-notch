from pathlib import Path

path = Path("boringNotch/managers/SystemStatsMonitor.swift")
source = path.read_text()
marker = "// MARK: - Thermal detail snapshot"

if marker not in source:
    source += r'''

// MARK: - Thermal detail snapshot
/// Lightweight detail state used by the expanded system-stats UI. It deliberately
/// reuses CPUTemperatureMonitor instead of creating another sensor polling loop.
struct ThermalDetailSnapshot {
    var hottestCPUCelsius: Double?
    var batteryCelsius: Double?

    static let empty = ThermalDetailSnapshot(
        hottestCPUCelsius: nil,
        batteryCelsius: nil
    )
}

@MainActor
final class ThermalDetailMonitor: ObservableObject {
    static let shared = ThermalDetailMonitor()

    @Published private(set) var snapshot = ThermalDetailSnapshot.empty

    private var observationTask: Task<Void, Never>?
    private static let expandedRefreshInterval = 1.0

    private init() {}

    deinit {
        observationTask?.cancel()
    }

    func setExpanded(_ isExpanded: Bool) {
        if isExpanded {
            guard observationTask == nil else { return }
            refresh()
            observationTask = Task { [weak self] in
                while let self, !Task.isCancelled {
                    self.refresh()
                    do {
                        try await Task.sleep(for: .seconds(Self.expandedRefreshInterval))
                    } catch {
                        return
                    }
                }
            }
        } else {
            observationTask?.cancel()
            observationTask = nil
        }
    }

    private func refresh() {
        // The helper currently exposes the CPU aggregate only. Keep battery nil until
        // a real sensor-backed value exists rather than presenting guessed telemetry.
        snapshot = ThermalDetailSnapshot(
            hottestCPUCelsius: CPUTemperatureMonitor.shared.averageCelsius,
            batteryCelsius: nil
        )
    }
}
'''
    path.write_text(source)

print("System stats thermal model present")
