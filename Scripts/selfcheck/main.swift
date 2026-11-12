import Foundation

// MARK: - VPNClassifier

precondition(VPNClassifier.isVPN(interface: "utun4", ignoring: []) == true,
             "utun is a tunnel interface")
precondition(VPNClassifier.isVPN(interface: "ipsec0", ignoring: []) == true,
             "ipsec is a tunnel interface")
precondition(VPNClassifier.isVPN(interface: "en0", ignoring: []) == false,
             "ethernet is not a tunnel")
precondition(VPNClassifier.isVPN(interface: "", ignoring: []) == false,
             "empty interface means unknown, not tunneled")
precondition(VPNClassifier.isVPN(interface: "  utun4 ", ignoring: []) == true,
             "surrounding whitespace is trimmed")
precondition(VPNClassifier.isVPN(interface: "utun4", ignoring: ["utun4"]) == false,
             "an ignored interface is not reported as a tunnel")
precondition(VPNClassifier.isVPN(interface: "utun10", ignoring: ["utun1"]) == true,
             "the ignore list matches whole names, never prefixes")

precondition(VPNClassifier.parseIgnoreList("utun0, utun1") == ["utun0", "utun1"],
             "comma separated")
precondition(VPNClassifier.parseIgnoreList("utun0 utun1") == ["utun0", "utun1"],
             "space separated")
precondition(VPNClassifier.parseIgnoreList("") == [],
             "empty string yields an empty set")
precondition(VPNClassifier.parseIgnoreList("  ,  ") == [],
             "separators only yields an empty set")

// MARK: - AgentHookPayload

let t0 = Date(timeIntervalSince1970: 1_000_000)

let blockedRaw = """
claude vscode ttys004
{"session_id":"abc123","cwd":"/Users/me/proj","hook_event_name":"Notification","message":"needs approval"}
"""
guard case .upsert(let blocked)? = AgentHookPayload.parse(blockedRaw, now: t0) else {
    fatalError("Notification payload should upsert a session")
}
precondition(blocked.id == "abc123")
precondition(blocked.tool == "claude")
precondition(blocked.termProgram == "vscode")
precondition(blocked.tty == "ttys004")
precondition(blocked.cwd == "/Users/me/proj")
precondition(blocked.state == .blocked, "Notification maps to blocked")
precondition(blocked.message == "needs approval")
precondition(blocked.updatedAt == t0)

let nonBlockingNotificationRaw = """
claude vscode ttys004
{"session_id":"abc123","cwd":"/Users/me/proj","hook_event_name":"Notification","notification_type":"auth_success","message":"Signed in"}
"""
guard case .upsert(let nonBlockingNotification)? = AgentHookPayload.parse(
    nonBlockingNotificationRaw, now: t0
) else {
    fatalError("a non-blocking Claude notification should upsert the session")
}
precondition(nonBlockingNotification.state == .working,
             "non-blocking Claude notifications must not look like user prompts")

let stopRaw = """
claude vscode ttys004
{"session_id":"abc123","cwd":"/Users/me/proj","hook_event_name":"Stop"}
"""
guard case .upsert(let stopped)? = AgentHookPayload.parse(stopRaw, now: t0) else {
    fatalError("Stop payload should upsert")
}
precondition(stopped.state == .done, "Stop maps to done")
precondition(stopped.message == nil)

let endRaw = """
claude vscode ttys004
{"session_id":"abc123","cwd":"/Users/me/proj","hook_event_name":"SessionEnd"}
"""
guard case .end(let endedID)? = AgentHookPayload.parse(endRaw, now: t0) else {
    fatalError("SessionEnd payload should end the session")
}
precondition(endedID == "abc123")

let unknownRaw = """
claude vscode ttys004
{"session_id":"abc123","cwd":"/Users/me/proj","hook_event_name":"SomeFutureHook"}
"""
guard case .upsert(let unknown)? = AgentHookPayload.parse(unknownRaw, now: t0) else {
    fatalError("an unknown hook must keep the session visible, not drop it")
}
precondition(unknown.state == .working, "unknown events degrade to working")

precondition(AgentHookPayload.parse("", now: t0) == nil,
             "empty input is not a payload")
precondition(AgentHookPayload.parse("claude vscode ttys004\nnot json", now: t0) == nil,
             "malformed JSON is not a payload")
precondition(AgentHookPayload.parse("claude vscode ttys004\n{\"cwd\":\"/x\"}", now: t0) == nil,
             "a payload without session_id cannot be keyed")

let sparseRaw = """
codex ? ?
{"session_id":"z","cwd":"/tmp","hook_event_name":"Stop"}
"""
guard case .upsert(let sparse)? = AgentHookPayload.parse(sparseRaw, now: t0) else {
    fatalError("the ? placeholders the hook writes must parse")
}
precondition(sparse.tool == "codex")
precondition(sparse.termProgram == nil, "? means unknown, stored as nil")
precondition(sparse.tty == nil, "? means unknown, stored as nil")

// Codex ships the same payload keys as Claude Code but has no Notification event;
// it raises PermissionRequest when it needs an approval. Body copied verbatim from
// a real codex 0.146.1 hook invocation.
let codexBlockedRaw = """
codex ghostty ttys006
{"session_id":"019fd6ed-8660-74a3-bf6b-e79c792c9fd1","transcript_path":"/x/rollout.jsonl","cwd":"/Users/me/proj","hook_event_name":"PermissionRequest"}
"""
guard case .upsert(let codexBlocked)? = AgentHookPayload.parse(codexBlockedRaw, now: t0) else {
    fatalError("a Codex hook payload must parse")
}
precondition(codexBlocked.state == .blocked, "PermissionRequest is Codex asking for you")
precondition(codexBlocked.projectName == "proj")

let codexEndRaw = """
codex ghostty ttys006
{"session_id":"019fd6ed","transcript_path":"/x/rollout.jsonl","cwd":"/Users/me/proj","hook_event_name":"SessionEnd","reason":"other"}
"""
guard case .end(let codexEndedID)? = AgentHookPayload.parse(codexEndRaw, now: t0) else {
    fatalError("Codex SessionEnd should end the session")
}
precondition(codexEndedID == "019fd6ed")

// A waiting state must be followed by hooks that report resumed work. Without
// these entries, approving a tool or submitting a reply leaves the session
// blocked until the turn stops.
let claudeHookConfig = AgentHookConfiguration.snippet(
    tool: "claude", scriptPath: "/tmp/bn-hook"
)
let codexHookConfig = AgentHookConfiguration.snippet(
    tool: "codex", scriptPath: "/tmp/bn-hook"
)

func hookGroups(in snippet: String) -> [String: Any] {
    guard let data = snippet.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hooks = json["hooks"] as? [String: Any]
    else { fatalError("generated hook config must be valid JSON") }
    return hooks
}

let claudeHookGroups = hookGroups(in: claudeHookConfig)
let codexHookGroups = hookGroups(in: codexHookConfig)
let recoveryEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse"]

for event in recoveryEvents {
    precondition(claudeHookGroups[event] != nil,
                 "Claude config must report resumed work via \(event)")
    precondition(codexHookGroups[event] != nil,
                 "Codex config must report resumed work via \(event)")
}

guard let notificationGroups = claudeHookGroups["Notification"] as? [[String: Any]],
      let notificationMatcher = notificationGroups.first?["matcher"] as? String
else { fatalError("Claude notifications must be restricted to waiting types") }
precondition(notificationMatcher.contains("permission_prompt"))
precondition(notificationMatcher.contains("idle_prompt"))
precondition(notificationMatcher.contains("elicitation_dialog"))
precondition(notificationMatcher.contains("agent_needs_input"))

// MARK: - AgentSessionReducer

func mk(_ id: String, _ state: AgentState, _ age: TimeInterval) -> AgentSession {
    AgentSession(id: id, tool: "claude", state: state, message: nil,
                 cwd: "/tmp", termProgram: nil, tty: nil,
                 updatedAt: t0.addingTimeInterval(-age))
}

precondition(AgentSessionReducer.worstState([]) == nil,
             "no sessions means no dot")
precondition(AgentSessionReducer.worstState([mk("a", .done, 0)]) == .done)
precondition(AgentSessionReducer.worstState([mk("a", .done, 0), mk("b", .working, 0)]) == .working,
             "working outranks done")
precondition(AgentSessionReducer.worstState([mk("a", .working, 0), mk("b", .blocked, 0)]) == .blocked,
             "blocked outranks everything")

let pruned = AgentSessionReducer.pruned(
    [mk("fresh", .working, 10), mk("stale", .working, 5000)],
    now: t0, staleAfter: 1800)
precondition(pruned.map(\.id) == ["fresh"],
             "a crashed agent must not pin a dot on forever")

// MARK: - HomeMiddlePanelMigration

let fresh = HomeMiddlePanelMigration.migrate(
    didMigrate: false, legacyShowCalendar: false, current: .agents)
precondition(fresh.panel == .none,
             "a user who had the calendar off keeps an empty middle slot")
precondition(fresh.didMigrate == true)

let hadCalendar = HomeMiddlePanelMigration.migrate(
    didMigrate: false, legacyShowCalendar: true, current: .agents)
precondition(hadCalendar.panel == .calendar,
             "a user who had the calendar on keeps the calendar")
precondition(hadCalendar.didMigrate == true)

let alreadyDone = HomeMiddlePanelMigration.migrate(
    didMigrate: true, legacyShowCalendar: true, current: .agents)
precondition(alreadyDone.panel == .agents,
             "migration is idempotent and must never overwrite a later user choice")
precondition(alreadyDone.didMigrate == true)

precondition(HomeMiddlePanel(rawValue: "calendar") == .calendar,
             "raw values are stable, they are persisted in user defaults")
precondition(HomeMiddlePanel.allCases.count == 3)

print("self-checks passed")
