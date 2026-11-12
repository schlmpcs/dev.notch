//
//  KeepAwakeManager.swift
//  boringNotch
//
//  The in-process equivalent of `caffeinate -d`: holds a PreventUserIdleDisplaySleep
//  power assertion while the user wants the display kept awake.
//
//  An assertion rather than a spawned caffeinate child, because the kernel releases
//  it when this process exits for any reason, including the SIGKILL install.sh sends,
//  so there is never an orphan left holding the display on.
//

import Combine
import Defaults
import Foundation
import IOKit.pwr_mgt
import os

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    /// True only while the assertion is actually held. The UI reads this, not the
    /// stored preference, so a failed assertion never shows as "awake".
    @Published private(set) var isActive: Bool = false

    private var assertionID = IOPMAssertionID(0)
    private var preferenceObserver: AnyCancellable?
    private let logger = Logger(subsystem: "theboringteam.boringnotch", category: "keepawake")

    private init() {
        // The publisher emits the stored value first, so a keep-awake that was on
        // before a relaunch is re-established here.
        preferenceObserver = Defaults.publisher(.keepDisplayAwake)
            .sink { [weak self] change in
                Task { @MainActor in self?.apply(change.newValue) }
            }
    }

    func toggle() {
        Defaults[.keepDisplayAwake].toggle()
    }

    private func apply(_ wanted: Bool) {
        if wanted {
            acquire()
        } else {
            release()
        }
    }

    private func acquire() {
        guard !isActive else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Keep Display Awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            logger.error("IOPMAssertionCreateWithName failed: \(result, privacy: .public)")
            // Do not leave the preference claiming the display is held awake.
            Defaults[.keepDisplayAwake] = false
            return
        }
        assertionID = id
        isActive = true
    }

    private func release() {
        guard isActive else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            logger.error("IOPMAssertionRelease failed: \(result, privacy: .public)")
        }
        assertionID = IOPMAssertionID(0)
        isActive = false
    }
}
