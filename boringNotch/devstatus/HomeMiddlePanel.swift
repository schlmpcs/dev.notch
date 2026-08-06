//
//  HomeMiddlePanel.swift
//  boringNotch
//
//  The open notch is a fixed 640x190 and its home HStack fits exactly one
//  middle panel between the music player and the camera preview. This enum is
//  which one. Foundation only, so Scripts/selfcheck.sh can compile it standalone.
//  The Defaults.Serializable conformance lives in Constants.swift.
//

import Foundation

public enum HomeMiddlePanel: String, CaseIterable, Identifiable {
    case none
    case calendar
    case agents

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .calendar: return "Calendar"
        case .agents: return "Agent sessions"
        }
    }
}

public enum HomeMiddlePanelMigration {
    /// Converts the old `showCalendar` boolean into the new one-of enum, exactly once.
    ///
    /// Guarded by its own flag rather than by inspecting `current`, because a user
    /// who deliberately picks `.calendar` later must not look like an unmigrated
    /// install on the next launch.
    public static func migrate(didMigrate: Bool,
                               legacyShowCalendar: Bool,
                               current: HomeMiddlePanel) -> (panel: HomeMiddlePanel, didMigrate: Bool) {
        guard !didMigrate else { return (current, true) }
        return (legacyShowCalendar ? .calendar : .none, true)
    }
}
