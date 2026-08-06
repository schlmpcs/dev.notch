//
//  VPNStatusManager.swift
//  boringNotch
//
//  Answers one question: is my traffic actually routed through a tunnel right now.
//
//  It reads the system's real default route rather than looking for the existence
//  of a tunnel interface, because "a utun device exists" and "my traffic goes
//  through it" are different facts and only the second one is useful.
//

import Combine
import Defaults
import Foundation
import Network
import SystemConfiguration

@MainActor
final class VPNStatusManager: ObservableObject {
    static let shared = VPNStatusManager()

    /// Name of the interface carrying the default route, e.g. "en0" or "utun4".
    @Published private(set) var primaryInterface: String = ""
    @Published private(set) var isTunneled: Bool = false
    /// True when the primary-interface read returned nothing. Surfaced in settings
    /// so a sandbox denial is visible rather than silently reading as "no VPN".
    @Published private(set) var readFailed: Bool = false
    @Published private(set) var egressIP: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "theboringteam.boringnotch.vpnpath")
    private var egressTask: Task<Void, Never>?

    private init() {
        // Event driven, so there is no polling timer and no idle battery cost.
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start(queue: monitorQueue)
        refresh()
    }

    func refresh() {
        let interface = Self.readPrimaryInterface()
        readFailed = interface == nil
        primaryInterface = interface ?? ""
        isTunneled = VPNClassifier.isVPN(
            interface: primaryInterface,
            ignoring: VPNClassifier.parseIgnoreList(Defaults[.vpnIgnoredInterfaces])
        )
        refreshEgressIP()
    }

    /// Reads State:/Network/Global/IPv4 -> PrimaryInterface.
    static func readPrimaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "boringNotch.vpn" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString),
              let dict = value as? [String: Any],
              let interface = dict["PrimaryInterface"] as? String
        else { return nil }
        return interface
    }

    private func refreshEgressIP() {
        egressTask?.cancel()
        guard Defaults[.showVPNEgressIP] else {
            egressIP = nil
            return
        }
        egressTask = Task { [weak self] in
            guard let url = URL(string: "https://api.ipify.org") else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let ip = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty
            else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.egressIP = ip }
        }
    }
}
