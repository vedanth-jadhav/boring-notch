//
//  ThermalDetailMonitor.swift
//  boringNotch
//

import Foundation

struct ThermalDetailSnapshot {
    var hottestCPUCelsius: Double?
    var batteryCelsius: Double?
    var lastUpdated: Date?

    static let empty = ThermalDetailSnapshot(
        hottestCPUCelsius: nil,
        batteryCelsius: nil,
        lastUpdated: nil
    )
}

@MainActor
final class ThermalDetailMonitor: ObservableObject {
    static let shared = ThermalDetailMonitor()

    @Published private(set) var snapshot = ThermalDetailSnapshot.empty

    private let client = XPCHelperClient.shared
    private var monitoringTask: Task<Void, Never>?

    private init() {}

    deinit {
        monitoringTask?.cancel()
    }

    func setExpanded(_ isExpanded: Bool) {
        if isExpanded {
            startMonitoring()
        } else {
            stopMonitoring(resetSnapshot: false)
        }
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func stopMonitoring(resetSnapshot: Bool) {
        monitoringTask?.cancel()
        monitoringTask = nil

        if resetSnapshot {
            snapshot = .empty
        }
    }

    private func refresh() async {
        async let hottestCPU = client.currentHottestCPUTemperature()
        async let battery = client.currentBatteryTemperature()

        snapshot = ThermalDetailSnapshot(
            hottestCPUCelsius: await hottestCPU,
            batteryCelsius: await battery,
            lastUpdated: Date()
        )
    }
}
