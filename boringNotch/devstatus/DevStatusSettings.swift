//
//  DevStatusSettings.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

struct DevStatusSettings: View {
    @ObservedObject private var vpn = VPNStatusManager.shared
    @Default(.homeMiddlePanel) private var homeMiddlePanel
    @Default(.vpnIgnoredInterfaces) private var ignoredInterfaces
    @Default(.showVPNEgressIP) private var showVPNEgressIP
    @Default(.agentAlertDuration) private var alertDuration
    @Default(.agentStaleTimeout) private var staleTimeout
    @State private var copiedConfig = false
    @State private var copiedDequarantine = false

    var body: some View {
        Form {
            Section(header: Text("Home middle panel")) {
                Picker("Middle panel", selection: $homeMiddlePanel) {
                    ForEach(HomeMiddlePanel.allCases) { panel in
                        Text(panel.displayName).tag(panel)
                    }
                }
                .pickerStyle(.inline)
                Text("The open notch fits one panel between the music player and the camera preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("VPN")) {
                Defaults.Toggle(key: .showVPNDot) {
                    Text("Show VPN dot")
                }
                LabeledContent("Primary interface") {
                    Text(vpn.readFailed ? "unavailable" : (vpn.primaryInterface.isEmpty ? "none" : vpn.primaryInterface))
                        .foregroundStyle(vpn.readFailed ? .red : .secondary)
                        .monospaced()
                }
                TextField("Interfaces to ignore", text: $ignoredInterfaces)
                    .textFieldStyle(.roundedBorder)
                Text("Comma or space separated whole interface names. iCloud Private Relay and an idle Tailscale daemon both create utun devices; exclude the specific one shown above if it is not your VPN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Defaults.Toggle(key: .showVPNEgressIP) {
                    Text("Look up egress IP")
                }
                .onChange(of: showVPNEgressIP) {
                    VPNStatusManager.shared.refresh()
                }
                Text("Off by default. This makes an outbound request to a third party every time your network changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let ip = vpn.egressIP {
                    LabeledContent("Egress IP") {
                        Text(ip).monospaced().foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Agents")) {
                Defaults.Toggle(key: .showAgentDot) {
                    Text("Show agent dot")
                }
                Slider(value: $alertDuration, in: 1...15, step: 1) {
                    Text("Alert duration: \(Int(alertDuration))s")
                }
                Slider(value: $staleTimeout, in: 300...7200, step: 300) {
                    Text("Drop silent sessions after: \(Int(staleTimeout / 60))m")
                }
            }

            Section(header: Text("Hook setup")) {
                Text("Add this to ~/.claude/settings.json, then restart your agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(copiedConfig ? "Copied" : "Copy hook config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            AgentSessionManager.shared.hookConfigSnippet, forType: .string)
                        copiedConfig = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedConfig = false
                        }
                    }
                    Button(copiedDequarantine ? "Copied" : "Copy de-quarantine command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "xattr -d com.apple.quarantine '\(AgentSessionManager.shared.hookScriptPath)'",
                            forType: .string)
                        copiedDequarantine = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedDequarantine = false
                        }
                    }
                }
                Text("macOS blocks execution of files this sandboxed app writes, so the hook fails the first time an agent invokes it until this command has been run once in Terminal. It only needs to be run again after an app update changes the script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Dev Status")
    }
}
