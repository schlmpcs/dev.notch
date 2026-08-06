//
//  SessionFocus.swift
//  boringNotch
//
//  Takes you from "an agent needs you" to the actual window it is waiting in.
//
//  Under VS Code, TERM_SESSION_ID is empty and there is no scriptable terminal-tab
//  handle, so there is nothing to target directly. What does work is matching the
//  editor window title against the last path component of the agent's cwd.
//

import AppKit
import Foundation

enum SessionFocus {
    /// TERM_PROGRAM is "vscode" for VS Code and for Cursor, so both are tried.
    private static let bundleIDs: [String: [String]] = [
        "vscode": ["com.microsoft.VSCode",
                   "com.microsoft.VSCodeInsiders",
                   "com.todesktop.230313mzl4w4u92"],
        "iTerm.app": ["com.googlecode.iterm2"],
        "Apple_Terminal": ["com.apple.Terminal"],
        "ghostty": ["com.mitchellh.ghostty"],
        "WezTerm": ["com.github.wez.wezterm"],
        "Alacritty": ["org.alacritty"]
    ]

    @MainActor
    static func focus(_ session: AgentSession) {
        guard let term = session.termProgram,
              let candidates = bundleIDs[term],
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  candidates.contains($0.bundleIdentifier ?? "")
              })
        else { return }

        // Activation is allowed from the sandbox; the AX window raise is not, so
        // that half goes to the helper.
        app.activate(options: [.activateAllWindows])

        let fragment = session.projectName
        guard !fragment.isEmpty else { return }
        Task {
            _ = await XPCHelperClient.shared.focusWindow(
                pid: app.processIdentifier, titleFragment: fragment)
        }
    }
}
