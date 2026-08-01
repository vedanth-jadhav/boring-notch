//
//  CaffeineManager.swift
//  boringNotch
//

import Foundation
import IOKit.pwr_mgt

final class CaffeineManager {
    static let shared = CaffeineManager()

    private var assertionID = IOPMAssertionID(0)

    private init() {}

    func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard assertionID == 0 else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "boring.notch lock screen widget" as CFString,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
        }
    }

    func stop() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
