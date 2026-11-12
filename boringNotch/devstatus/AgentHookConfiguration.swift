//
//  AgentHookConfiguration.swift
//  boringNotch
//
//  Pure hook-config generation shared by the app and Scripts/selfcheck.sh.
//

import Foundation

public enum AgentHookConfiguration {
    private struct HookSpec {
        let event: String
        let matcher: String?
    }

    public static let blockingNotificationTypes = [
        "permission_prompt",
        "idle_prompt",
        "elicitation_dialog",
        "agent_needs_input",
        "workflow_permission_prompt",
        "worker_permission_prompt",
    ]

    private static var waitingNotificationMatcher: String {
        blockingNotificationTypes.joined(separator: "|")
    }

    public static func isBlockingNotification(_ type: String) -> Bool {
        blockingNotificationTypes.contains(type)
    }

    public static func snippet(tool: String, scriptPath: String) -> String {
        let specs: [HookSpec]
        switch tool {
        case "codex":
            specs = [
                HookSpec(event: "SessionStart", matcher: nil),
                HookSpec(event: "UserPromptSubmit", matcher: nil),
                HookSpec(event: "PermissionRequest", matcher: nil),
                HookSpec(event: "PreToolUse", matcher: nil),
                HookSpec(event: "PostToolUse", matcher: nil),
                HookSpec(event: "Stop", matcher: nil),
                HookSpec(event: "SessionEnd", matcher: nil),
            ]
        default:
            specs = [
                HookSpec(event: "SessionStart", matcher: nil),
                HookSpec(event: "UserPromptSubmit", matcher: nil),
                HookSpec(event: "Notification", matcher: waitingNotificationMatcher),
                HookSpec(event: "PreToolUse", matcher: nil),
                HookSpec(event: "PostToolUse", matcher: nil),
                HookSpec(event: "Stop", matcher: nil),
                HookSpec(event: "SessionEnd", matcher: nil),
            ]
        }

        let command = "'\(scriptPath)' \(tool)"
        var hooks: [String: Any] = [:]

        for spec in specs {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command]],
            ]
            if let matcher = spec.matcher {
                group["matcher"] = matcher
            }
            hooks[spec.event] = [group]
        }

        let root: [String: Any] = ["hooks": hooks]
        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
