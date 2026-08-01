//
//  SystemStatsMonitor.swift
//  boringNotch
//

import Combine
import Darwin
import Foundation

struct SystemStatsSnapshot {
    var cpuUsage: Double?
    var memoryUsage: Double?
    var usedMemoryBytes: UInt64?
    var totalMemoryBytes: UInt64
    var temperatureCelsius: Double?
    var cpuHistory: [Double]
    var memoryHistory: [Double]
    var temperatureHistory: [Double]
    var lastUpdated: Date?

    static let empty = SystemStatsSnapshot(
        cpuUsage: nil,
        memoryUsage: nil,
        usedMemoryBytes: nil,
        totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
        temperatureCelsius: nil,
        cpuHistory: [],
        memoryHistory: [],
        temperatureHistory: [],
        lastUpdated: nil
    )
}

@MainActor
final class SystemStatsMonitor: ObservableObject {
    static let shared = SystemStatsMonitor()

    @Published private(set) var snapshot = SystemStatsSnapshot.empty

    private static let closedRefreshInterval = 3.0
    private static let openRefreshInterval = 1.0
    private static let maximumSampleCount = 64
    private static let percentageRange = 0.0...1.0
    private static let temperatureRange = 30.0...100.0
    private static let cpuStateCount = Int(CPU_STATE_MAX)
    private static let cpuStateUser = Int(CPU_STATE_USER)
    private static let cpuStateSystem = Int(CPU_STATE_SYSTEM)
    private static let cpuStateIdle = Int(CPU_STATE_IDLE)
    private static let cpuStateNice = Int(CPU_STATE_NICE)

    private var previousProcessorTicks: [UInt64]?
    private var monitoringTask: Task<Void, Never>?
    private var refreshInterval = closedRefreshInterval

    private init() {}

    deinit {
        monitoringTask?.cancel()
    }

    func setIslandOpen(_ isOpen: Bool) {
        let nextInterval = isOpen ? Self.openRefreshInterval : Self.closedRefreshInterval
        refreshInterval = nextInterval

        if isOpen {
            guard monitoringTask == nil else { return }
            startMonitoring()
        } else {
            monitoringTask?.cancel()
            monitoringTask = nil
        }
    }

    func refreshNow() {
        refresh()
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.refresh()

                do {
                    try await Task.sleep(for: .seconds(self.refreshInterval))
                } catch {
                    return
                }
            }
        }
    }

    private func refresh() {
        let cpuUsage = readCPUUsage()
        let memory = readMemoryUsage()
        let temperature = CPUTemperatureMonitor.shared.averageCelsius

        snapshot = SystemStatsSnapshot(
            cpuUsage: cpuUsage,
            memoryUsage: memory?.usage,
            usedMemoryBytes: memory?.usedBytes,
            totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            temperatureCelsius: temperature,
            cpuHistory: append(cpuUsage, to: snapshot.cpuHistory, range: Self.percentageRange),
            memoryHistory: append(memory?.usage, to: snapshot.memoryHistory, range: Self.percentageRange),
            temperatureHistory: append(temperature, to: snapshot.temperatureHistory, range: Self.temperatureRange),
            lastUpdated: Date()
        )
    }

    private func append(_ value: Double?, to history: [Double], range: ClosedRange<Double>) -> [Double] {
        var updated = history

        if let value {
            updated.append(min(max(value, range.lowerBound), range.upperBound))
        } else if let last = updated.last {
            updated.append(last)
        }

        if updated.count > Self.maximumSampleCount {
            updated.removeFirst(updated.count - Self.maximumSampleCount)
        }

        return updated
    }

    private func readCPUUsage() -> Double? {
        guard let ticks = readProcessorTicks() else { return nil }
        defer { previousProcessorTicks = ticks }

        guard let previousProcessorTicks, previousProcessorTicks.count == ticks.count else { return nil }

        var totalDelta: UInt64 = 0
        var idleDelta: UInt64 = 0

        for index in stride(from: 0, to: ticks.count, by: Self.cpuStateCount) {
            let currentUser = ticks[index + Self.cpuStateUser]
            let currentSystem = ticks[index + Self.cpuStateSystem]
            let currentIdle = ticks[index + Self.cpuStateIdle]
            let currentNice = ticks[index + Self.cpuStateNice]

            let previousUser = previousProcessorTicks[index + Self.cpuStateUser]
            let previousSystem = previousProcessorTicks[index + Self.cpuStateSystem]
            let previousIdle = previousProcessorTicks[index + Self.cpuStateIdle]
            let previousNice = previousProcessorTicks[index + Self.cpuStateNice]

            totalDelta +=
                (currentUser &- previousUser) +
                (currentSystem &- previousSystem) +
                (currentIdle &- previousIdle) +
                (currentNice &- previousNice)

            idleDelta += currentIdle &- previousIdle
        }

        guard totalDelta > 0 else { return nil }

        let activeDelta = totalDelta - idleDelta
        return min(max(Double(activeDelta) / Double(totalDelta), 0), 1)
    }

    private func readProcessorTicks() -> [UInt64]? {
        var processorInfoArray: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfoArray,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfoArray else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: processorInfoArray),
                vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let buffer = UnsafeBufferPointer(start: processorInfoArray, count: Int(processorInfoCount))
        return buffer.map(UInt64.init)
    }

    private func readMemoryUsage() -> (usage: Double, usedBytes: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        let usedPages =
            UInt64(stats.internal_page_count) +
            UInt64(stats.wire_count) +
            UInt64(stats.compressor_page_count)
            - UInt64(min(stats.purgeable_count, stats.internal_page_count))

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let usedBytes = min(usedPages * UInt64(pageSize), totalBytes)

        guard totalBytes > 0 else { return nil }

        return (Double(usedBytes) / Double(totalBytes), usedBytes)
    }
}
