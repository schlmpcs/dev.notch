//
//  VPNClassifier.swift
//  boringNotch
//
//  Pure interface-name classification. Foundation only, so Scripts/selfcheck.sh
//  can compile this file standalone. Do not import Defaults, SwiftUI or AppKit here.
//

import Foundation

public enum VPNClassifier {
    /// Interface name prefixes macOS uses for tunnel devices.
    public static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    /// Whether the machine's primary interface is a tunnel the user cares about.
    ///
    /// `ignoring` holds whole interface names, not prefixes. iCloud Private Relay
    /// and an idle Tailscale daemon both create utun devices, so the user needs to
    /// be able to exclude a specific one without excluding every tunnel.
    public static func isVPN(interface: String, ignoring: Set<String>) -> Bool {
        let name = interface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !ignoring.contains(name) else { return false }
        return tunnelPrefixes.contains { name.hasPrefix($0) }
    }

    /// Parses the user's free-text ignore list. Accepts commas, spaces and newlines.
    public static func parseIgnoreList(_ raw: String) -> Set<String> {
        let parts = raw.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
        return Set(parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty })
    }
}
