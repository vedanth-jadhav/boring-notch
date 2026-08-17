//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Average CPU temperature access using the Stats-derived SMC reader
    func currentAverageCPUTemperature(with reply: @escaping (NSNumber?) -> Void)
    func currentHottestCPUTemperature(with reply: @escaping (NSNumber?) -> Void)
    func currentBatteryTemperature(with reply: @escaping (NSNumber?) -> Void)
    // Stages a verified beta DMG and launches a detached installer that replaces this app after exit.
    func prepareUpdateInstallation(fromDMGPath dmgPath: String, currentAppPath: String, hostPID: Int32, with reply: @escaping (Bool) -> Void)
}
