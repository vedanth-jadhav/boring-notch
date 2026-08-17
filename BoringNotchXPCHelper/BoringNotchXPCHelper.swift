//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    private static let temperatureReader = StatsCPUTemperatureReader()
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - CPU Temperature

    @objc func currentAverageCPUTemperature(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.temperatureReader.currentAverageCelsius().map(NSNumber.init(value:)))
    }

    @objc func currentHottestCPUTemperature(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.temperatureReader.currentHottestCelsius().map(NSNumber.init(value:)))
    }

    @objc func currentBatteryTemperature(with reply: @escaping (NSNumber?) -> Void) {
        reply(currentBatteryTemperatureCelsius().map(NSNumber.init(value:)))
    }

    // MARK: - Self Update

    @objc func prepareUpdateInstallation(
        fromDMGPath dmgPath: String,
        currentAppPath: String,
        hostPID: Int32,
        with reply: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            do {
                try Self.stageUpdateAndLaunchInstaller(
                    dmgPath: dmgPath,
                    currentAppPath: currentAppPath,
                    hostPID: hostPID
                )
                reply(true)
            } catch {
                NSLog("Boring Notch update staging failed: %@", error.localizedDescription)
                reply(false)
            }
        }
    }

    private static func stageUpdateAndLaunchInstaller(
        dmgPath: String,
        currentAppPath: String,
        hostPID: Int32
    ) throws {
        let fileManager = FileManager.default
        let dmgURL = URL(fileURLWithPath: dmgPath).standardizedFileURL
        let currentAppURL = URL(fileURLWithPath: currentAppPath).standardizedFileURL

        guard dmgURL.pathExtension.lowercased() == "dmg", fileManager.fileExists(atPath: dmgURL.path) else {
            throw UpdateStagingError.invalidDMG
        }
        guard currentAppURL.pathExtension.lowercased() == "app", fileManager.fileExists(atPath: currentAppURL.path) else {
            throw UpdateStagingError.invalidCurrentApp
        }
        guard fileManager.isWritableFile(atPath: currentAppURL.deletingLastPathComponent().path) else {
            throw UpdateStagingError.currentAppLocationNotWritable
        }

        let stagingRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("boring-notch-update-\(UUID().uuidString)", isDirectory: true)
        let mountPoint = stagingRoot.appendingPathComponent("mount", isDirectory: true)
        let stagedApp = stagingRoot.appendingPathComponent("boringNotch.app", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        var mounted = false
        defer {
            if mounted {
                try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            }
        }

        try runProcess(
            "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, dmgURL.path]
        )
        mounted = true

        let mountedItems = try fileManager.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let sourceApp = mountedItems.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw UpdateStagingError.missingAppInDMG
        }

        try runProcess("/usr/bin/ditto", arguments: [sourceApp.path, stagedApp.path])

        guard let currentBundleIdentifier = Bundle(url: currentAppURL)?.bundleIdentifier,
              let stagedBundleIdentifier = Bundle(url: stagedApp)?.bundleIdentifier,
              currentBundleIdentifier == stagedBundleIdentifier else {
            throw UpdateStagingError.bundleIdentifierMismatch
        }

        try runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
        mounted = false

        let installerScript = stagingRoot.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/sh
        set -u
        pid="$1"
        current="$2"
        staged="$3"
        staging_root="$4"
        backup="${current}.boringnotch-backup"

        while /bin/kill -0 "$pid" >/dev/null 2>&1; do
            /bin/sleep 0.20
        done

        /bin/rm -rf "$backup"
        if [ -e "$current" ]; then
            /bin/mv "$current" "$backup" || exit 1
        fi

        if /usr/bin/ditto "$staged" "$current"; then
            /usr/bin/open "$current" >/dev/null 2>&1 || true
            /bin/rm -rf "$backup" "$staging_root"
            exit 0
        fi

        /bin/rm -rf "$current"
        if [ -e "$backup" ]; then
            /bin/mv "$backup" "$current" || true
            /usr/bin/open "$current" >/dev/null 2>&1 || true
        fi
        exit 1
        """
        try script.write(to: installerScript, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: installerScript.path)

        // Use nohup in a detached shell so the installer survives the XPC connection and host
        // app terminating. Paths are passed as positional arguments rather than interpolated.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = [
            "-c",
            "/usr/bin/nohup /bin/sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" >/dev/null 2>&1 </dev/null &",
            "boring-notch-updater",
            installerScript.path,
            String(hostPID),
            currentAppURL.path,
            stagedApp.path,
            stagingRoot.path
        ]
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
        launcher.waitUntilExit()
        guard launcher.terminationStatus == 0 else {
            throw UpdateStagingError.installerLaunchFailed
        }
    }

    private static func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateStagingError.commandFailed(executable)
        }
    }

    private enum UpdateStagingError: LocalizedError {
        case invalidDMG
        case invalidCurrentApp
        case currentAppLocationNotWritable
        case missingAppInDMG
        case bundleIdentifierMismatch
        case installerLaunchFailed
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDMG: return "Invalid update DMG."
            case .invalidCurrentApp: return "The running app path is invalid."
            case .currentAppLocationNotWritable: return "The running app location is not writable."
            case .missingAppInDMG: return "The update DMG does not contain an app bundle."
            case .bundleIdentifierMismatch: return "The update bundle identifier does not match the running app."
            case .installerLaunchFailed: return "Could not launch the detached update installer."
            case .commandFailed(let command): return "Update staging command failed: \(command)"
            }
        }
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private func currentBatteryTemperatureCelsius() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        if let rawTemperature = dictionary["Temperature"] as? NSNumber {
            return batteryTemperatureCelsius(from: rawTemperature.doubleValue)
        }

        if let rawVirtualTemperature = dictionary["VirtualTemperature"] as? NSNumber {
            return batteryTemperatureCelsius(from: rawVirtualTemperature.doubleValue)
        }

        return nil
    }

    private func batteryTemperatureCelsius(from rawValue: Double) -> Double {
        if (2000...4000).contains(rawValue) {
            return (rawValue / 10.0) - 273.15
        }

        if (200...1000).contains(rawValue) {
            return rawValue / 10.0
        }

        return rawValue / 100.0
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
