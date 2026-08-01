//
//  CPUTemperatureMonitor.swift
//  boringNotch
//

import Combine
import Foundation

@MainActor
final class CPUTemperatureMonitor: ObservableObject {
    static let shared = CPUTemperatureMonitor()

    @Published private(set) var averageCelsius: Double?
    @Published private var previewAverageCelsius: Double?

    private let client = XPCHelperClient.shared
    private var monitoringTask: Task<Void, Never>?

    static let fireStartCelsius = 90.0
    private static let idleRefreshInterval = 5.0
    private static let warmRefreshInterval = 2.0

    private init() {
        startMonitoring()
    }

    deinit {
        monitoringTask?.cancel()
    }

    var fireState: CPUFireState {
        Self.fireState(for: previewAverageCelsius ?? averageCelsius)
    }

    func setFirePreviewTemperature(_ temperature: Double?) {
        previewAverageCelsius = temperature
    }

    static func fireState(for averageCelsius: Double?) -> CPUFireState {
        guard let averageCelsius else { return .none }

        return averageCelsius > fireStartCelsius ? .fire : .none
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()

                do {
                    try await Task.sleep(for: .seconds(Self.refreshInterval(for: self.averageCelsius)))
                } catch {
                    return
                }
            }
        }
    }

    private func refresh() async {
        let average = await client.currentAverageCPUTemperature()

        if average != averageCelsius {
            averageCelsius = average
        }
    }

    private static func refreshInterval(for average: Double?) -> Double {
        guard let average, average > fireStartCelsius else {
            return idleRefreshInterval
        }

        return warmRefreshInterval
    }
}

enum CPUFireState: Equatable {
    case none
    case fire
}
