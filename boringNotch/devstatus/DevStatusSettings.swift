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
    @State private var copiedCodexConfig = false
    @State private var copiedDequarantine = false

    /// Copies and flips the button label back after a beat, so the three copy
    /// buttons do not each carry their own clipboard-and-timer block.
    private func copy(_ text: String, into flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            flag.wrappedValue = false
        }
    }

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

            Section(header: Text("Keep awake")) {
                Defaults.Toggle(key: .keepDisplayAwake) {
                    Text("Keep display awake")
                }
                Defaults.Toggle(key: .showKeepAwakeButton) {
                    Text("Show button in notch")
                }
                Defaults.Toggle(key: .showKeepAwakeGlyph) {
                    Text("Show full moon on closed notch")
                }
                Text("Same as caffeinate -d: the display and the Mac stay awake until you turn it off. Released automatically if the app quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Add the Claude config to ~/.claude/settings.json, the Codex config to ~/.codex/hooks.json, then restart your agent. Codex asks you to trust a hook the first time it runs one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(copiedConfig ? "Copied" : "Copy Claude hook config") {
                        copy(AgentSessionManager.shared.hookConfigSnippet, into: $copiedConfig)
                    }
                    Button(copiedCodexConfig ? "Copied" : "Copy Codex hook config") {
                        copy(AgentSessionManager.shared.codexHookConfigSnippet,
                             into: $copiedCodexConfig)
                    }
                }
                HStack {
                    Button(copiedDequarantine ? "Copied" : "Copy de-quarantine command") {
                        copy("xattr -d com.apple.quarantine '\(AgentSessionManager.shared.hookScriptPath)'",
                             into: $copiedDequarantine)
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
