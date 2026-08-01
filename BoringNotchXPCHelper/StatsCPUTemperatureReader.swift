//
//  StatsCPUTemperatureReader.swift
//  BoringNotchXPCHelper
//
//  The sensor keys and read-only SMC access are adapted from exelban/stats:
//  https://github.com/exelban/stats
//  Copyright (c) 2019 Serhiy Mytrovtsiy, licensed under the MIT License.
//  See THIRD_PARTY_NOTICES.md.
//

import Darwin
import Foundation
import IOKit

final class StatsCPUTemperatureReader {
    private enum DataType: String {
        case ui8 = "ui8 "
        case ui16 = "ui16"
        case ui32 = "ui32"
        case sp1e = "sp1e"
        case sp3c = "sp3c"
        case sp4b = "sp4b"
        case sp5a = "sp5a"
        case sp69 = "sp69"
        case sp78 = "sp78"
        case sp87 = "sp87"
        case sp96 = "sp96"
        case spa5 = "spa5"
        case spb4 = "spb4"
        case spf0 = "spf0"
        case flt = "flt "
        case fpe2 = "fpe2"
    }

    private enum Command: UInt8 {
        case kernelIndex = 2
        case readBytes = 5
        case readKeyInfo = 9
    }

    private struct KeyData {
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        struct Version {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }

        struct LimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: IOByteCount32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var version = Version()
        var limitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct Value {
        let key: String
        var dataSize: UInt32 = 0
        var dataType = ""
        var bytes = Array(repeating: UInt8(0), count: 32)
    }

    private static let m1Keys = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"
    ]
    private static let m2Keys = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"
    ]
    private static let m3Keys = [
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B",
        "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
    ]
    private static let m4Keys = [
        "Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05",
        "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"
    ]
    private static let m5Keys = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U",
        "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
    ]

    private var connection: io_connect_t = 0
    private let temperatureKeys: [String]

    init() {
        temperatureKeys = Self.temperatureKeys(for: Self.processorBrand())
        openConnection()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func currentAverageCelsius() -> Double? {
        let values = currentCPUValues()
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func currentHottestCelsius() -> Double? {
        currentCPUValues().max()
    }

    private func currentCPUValues() -> [Double] {
        let values = temperatureKeys
            .compactMap(readValue)
            .filter { $0 >= 10 && $0 < 110 }
        return values
    }

    private func openConnection() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        ) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }

        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            connection = 0
            return
        }
    }

    private func readValue(for key: String) -> Double? {
        guard connection != 0 else { return nil }

        var value = Value(key: key)
        guard read(&value) == kIOReturnSuccess, value.dataSize > 0 else { return nil }

        switch DataType(rawValue: value.dataType) {
        case .ui8:
            return Double(value.bytes[0])
        case .ui16:
            return Double(unsigned16(value.bytes[0], value.bytes[1]))
        case .ui32:
            return Double(unsigned32(value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3]))
        case .sp1e:
            return Double(unsigned16(value.bytes[0], value.bytes[1])) / 16384
        case .sp3c:
            return Double(unsigned16(value.bytes[0], value.bytes[1])) / 4096
        case .sp4b:
            return Double(unsigned16(value.bytes[0], value.bytes[1])) / 2048
        case .sp5a:
            return Double(unsigned16(value.bytes[0], value.bytes[1])) / 1024
        case .sp69:
            return Double(unsigned16(value.bytes[0], value.bytes[1])) / 512
        case .sp78:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 256
        case .sp87:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 128
        case .sp96:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 64
        case .spa5:
            return Double(unsigned16(value.bytes[0], value.bytes[1])) / 32
        case .spb4:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 16
        case .spf0:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1]))
        case .flt:
            var result: Float = 0
            withUnsafeMutableBytes(of: &result) { bytes in
                bytes.copyBytes(from: value.bytes.prefix(MemoryLayout<Float>.size))
            }
            return result.isFinite ? Double(result) : nil
        case .fpe2:
            return Double((Int(value.bytes[0]) << 6) + (Int(value.bytes[1]) >> 2))
        case .none:
            return nil
        }
    }

    private func read(_ value: inout Value) -> kern_return_t {
        guard let key = fourCharacterCode(value.key) else { return kIOReturnBadArgument }

        var input = KeyData()
        var output = KeyData()
        input.key = key
        input.data8 = Command.readKeyInfo.rawValue

        var result = call(Command.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        value.dataSize = UInt32(output.keyInfo.dataSize)
        value.dataType = fourCharacterString(output.keyInfo.dataType)
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue

        result = call(Command.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        let dataSize = min(Int(value.dataSize), value.bytes.count)
        withUnsafeBytes(of: output.bytes) { outputBytes in
            value.bytes.replaceSubrange(0..<dataSize, with: outputBytes.prefix(dataSize))
        }
        return kIOReturnSuccess
    }

    private func call(_ index: UInt8, input: inout KeyData, output: inout KeyData) -> kern_return_t {
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(connection, UInt32(index), &input, inputSize, &output, &outputSize)
    }

    private func fourCharacterCode(_ value: String) -> UInt32? {
        let bytes = Array(value.utf8)
        guard bytes.count == 4 else { return nil }
        return unsigned32(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    private func fourCharacterString(_ value: UInt32) -> String {
        String(bytes: [
            UInt8(value >> 24 & 0xff),
            UInt8(value >> 16 & 0xff),
            UInt8(value >> 8 & 0xff),
            UInt8(value & 0xff)
        ], encoding: .ascii) ?? ""
    }

    private func unsigned16(_ first: UInt8, _ second: UInt8) -> UInt16 {
        UInt16(first) << 8 | UInt16(second)
    }

    private func unsigned32(_ first: UInt8, _ second: UInt8, _ third: UInt8, _ fourth: UInt8) -> UInt32 {
        UInt32(first) << 24 | UInt32(second) << 16 | UInt32(third) << 8 | UInt32(fourth)
    }

    private static func temperatureKeys(for brand: String) -> [String] {
        if brand.contains("Apple M5") { return m5Keys }
        if brand.contains("Apple M4") { return m4Keys }
        if brand.contains("Apple M3") { return m3Keys }
        if brand.contains("Apple M2") { return m2Keys }
        if brand.contains("Apple M1") { return m1Keys }

        if brand.contains("Apple") {
            return Array(Set(m1Keys + m2Keys + m3Keys + m4Keys + m5Keys)).sorted()
        }

        return (0..<10).flatMap { ["TC\($0)c", "TC\($0)C"] }
    }

    private static func processorBrand() -> String {
        var byteCount = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &byteCount, nil, 0) == 0,
              byteCount > 0 else { return "" }

        var bytes = Array(repeating: CChar(0), count: byteCount)
        let result = bytes.withUnsafeMutableBufferPointer { buffer in
            sysctlbyname("machdep.cpu.brand_string", buffer.baseAddress, &byteCount, nil, 0)
        }
        guard result == 0 else { return "" }
        return String(cString: bytes)
    }
}
