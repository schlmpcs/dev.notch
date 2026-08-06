# Dev Status in the Notch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show VPN tunnel state and coding-agent attention state in the closed notch, with a click-to-focus agent panel replacing the calendar's slot in the open notch.

**Architecture:** Two independent managers feed a new display layer. `VPNStatusManager` reads the system's actual default-route interface on `NWPathMonitor` events. `AgentSessionManager` watches a directory inside the app container that a shell hook writes into, treating it as an event queue rather than a state store. All decision logic lives in pure, Foundation-only files so it can be compiled and checked outside Xcode.

**Tech Stack:** Swift 6.3.3, SwiftUI, Network framework (`NWPathMonitor`), SystemConfiguration (`SCDynamicStore`), Dispatch (`DispatchSourceFileSystemObject`), ApplicationServices (Accessibility, in the XPC helper only), `Defaults` (already a dependency), `AsyncXPCConnection` (already a dependency).

## Global Constraints

- **No new SPM dependencies.** Everything here uses system frameworks or packages already in the project.
- **The main app is sandboxed.** `boringNotch/boringNotch.entitlements` sets `com.apple.security.app-sandbox = true`. No reads outside the container, no process enumeration, no Accessibility API.
- **The XPC helper is not sandboxed** (`BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements`) and already holds Accessibility authorization. Anything needing AX goes there.
- **Do not delete calendar code.** This repo is a fork of `TheBoredTeam/boring.notch`. Deleting upstream files causes recurring merge conflicts. Gate, do not remove.
- **The open notch is a fixed 640x190** (`boringNotch/sizing/matters.swift:16`). The home `HStack` fits exactly one middle panel.
- **No new Xcode targets and no `project.pbxproj` edits.** Both are avoidable; see Task 1 (checks run via `swiftc`) and Task 6 (hook script written at runtime, not bundled).
- **Pure files import Foundation only.** `VPNClassifier.swift`, `AgentSessionState.swift`, and `HomeMiddlePanel.swift` must compile standalone with `swiftc`. No `Defaults`, no SwiftUI, no AppKit in those three files. Protocol conformances for them live in `Constants.swift`.
- **Push target:** `git push` goes to `dev` (`schlmpcs/dev.notch`). The `origin` push URL is disabled. Commit identity is `schlmpcs <izimov.amir@gmail.com>`, already set locally.
- **No `Co-authored-by` trailers on commits. No em dashes in committed prose.**

## Deviations from the spec, with rationale

Two refinements were made while planning. Both preserve the spec's intent and remove a blocker.

1. **Checks run via `swiftc`, not from a `#Preview`.** The spec called for `#if DEBUG` asserts driven from a SwiftUI preview. A preview cannot be run from a script, so it gives no red/green cycle an implementer can execute. Instead, `Scripts/selfcheck.sh` compiles the pure files plus a `main.swift` of `precondition` calls and runs the binary. Same outcome (no new Xcode target), but actually runnable. Verified working before this plan was written.
2. **`bn-hook` is written to the container at launch, not bundled in `Contents/Resources`.** Bundling it requires adding a Copy Bundle Resources entry to `project.pbxproj`. Writing it at launch avoids that edit entirely, keeps the script and its parser in one file so the header format cannot drift, and is still zero manual install for the user.

## File Structure

**Create (pure, Foundation only, compiled by both Xcode and `swiftc`):**
- `boringNotch/managers/VPNClassifier.swift` - interface-name classification and ignore-list parsing.
- `boringNotch/managers/AgentSessionState.swift` - `AgentState`, `AgentSession`, hook payload parsing, state reducers.
- `boringNotch/models/HomeMiddlePanel.swift` - the middle-slot enum and its one-time migration.

**Create (app):**
- `boringNotch/managers/VPNStatusManager.swift` - live VPN observation.
- `boringNotch/managers/AgentSessionManager.swift` - queue watcher and hook script installer.
- `boringNotch/components/Notch/StatusDots.swift` - the two closed-notch dots.
- `boringNotch/components/Live activities/AgentAlertView.swift` - the preempting blocked alert.
- `boringNotch/components/Agents/AgentPanelView.swift` - the open-notch middle panel.
- `boringNotch/components/Settings/DevStatusSettings.swift` - the settings pane.

**Create (checks):**
- `Scripts/selfcheck/main.swift`
- `Scripts/selfcheck.sh`

**Modify:**
- `boringNotch/models/Constants.swift` - new `Defaults.Keys`, `Defaults.Serializable` conformance for `HomeMiddlePanel`.
- `boringNotch/ContentView.swift` - dot overlay, chin width, blocked-alert branch.
- `boringNotch/components/Notch/NotchHomeView.swift:232,442-466` - middle slot switch.
- `boringNotch/components/Settings/SettingsView.swift:39-41,80-81,710-806` - new pane, calendar toggle replaced by the picker.
- `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift` and `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift` - `focusWindow`. **These two files must stay byte-identical in their protocol declaration.**
- `BoringNotchXPCHelper/BoringNotchXPCHelper.swift` - AX window raise.
- `boringNotch/XPCHelperClient/XPCHelperClient.swift` - client wrapper.
- `boringNotch/boringNotchApp.swift` - manager startup.

---

### Task 1: Self-check harness and VPN classifier

**Files:**
- Create: `boringNotch/managers/VPNClassifier.swift`
- Create: `Scripts/selfcheck/main.swift`
- Create: `Scripts/selfcheck.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `VPNClassifier.isVPN(interface: String, ignoring: Set<String>) -> Bool`, `VPNClassifier.parseIgnoreList(_ raw: String) -> Set<String>`, and `Scripts/selfcheck.sh` as the project's check command for every later task.

- [ ] **Step 1: Create the check runner script**

```bash
mkdir -p Scripts/selfcheck
cat > Scripts/selfcheck.sh <<'SH'
#!/bin/sh
# Compiles the pure (Foundation-only) logic files together with the check
# entry point and runs them. Deliberately independent of Xcode so the logic
# has a red/green cycle without adding a test target.
set -e
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/selfcheck"
swiftc -o "$OUT" \
  boringNotch/managers/VPNClassifier.swift \
  boringNotch/managers/AgentSessionState.swift \
  boringNotch/models/HomeMiddlePanel.swift \
  Scripts/selfcheck/main.swift
"$OUT"
SH
chmod +x Scripts/selfcheck.sh
```

Note: the script references three pure files. Tasks 2 and 3 create the other two. To keep Task 1 runnable on its own, create empty placeholders now and fill them in later:

```bash
printf 'import Foundation\n' > boringNotch/managers/AgentSessionState.swift
printf 'import Foundation\n' > boringNotch/models/HomeMiddlePanel.swift
```

- [ ] **Step 2: Write the failing checks**

Create `Scripts/selfcheck/main.swift`:

```swift
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

print("self-checks passed")
```

- [ ] **Step 3: Run the checks to verify they fail**

Run: `./Scripts/selfcheck.sh`
Expected: FAIL at compile time, `cannot find 'VPNClassifier' in scope`.

- [ ] **Step 4: Write the minimal implementation**

Create `boringNotch/managers/VPNClassifier.swift`:

```swift
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
```

- [ ] **Step 5: Run the checks to verify they pass**

Run: `./Scripts/selfcheck.sh`
Expected: `self-checks passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add Scripts boringNotch/managers/VPNClassifier.swift boringNotch/managers/AgentSessionState.swift boringNotch/models/HomeMiddlePanel.swift
git commit -m "Add selfcheck harness and VPN interface classifier"
```

---

### Task 2: Agent session model, hook payload parser, reducers

**Files:**
- Modify: `boringNotch/managers/AgentSessionState.swift` (currently the placeholder from Task 1)
- Modify: `Scripts/selfcheck/main.swift`

**Interfaces:**
- Consumes: nothing from Task 1 beyond the runner script.
- Produces: `AgentState` (`.working`, `.blocked`, `.done`), `AgentSession` struct, `AgentHookPayload.parse(_ raw: String, now: Date) -> AgentHookResult?`, `AgentHookResult` (`.upsert(AgentSession)`, `.end(id: String)`), `AgentSessionReducer.worstState(_:) -> AgentState?`, `AgentSessionReducer.pruned(_:now:staleAfter:) -> [AgentSession]`. Tasks 6, 8, 9 and 10 all depend on these exact names.

- [ ] **Step 1: Write the failing checks**

Append to `Scripts/selfcheck/main.swift`, before the final `print`:

```swift
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
```

- [ ] **Step 2: Run the checks to verify they fail**

Run: `./Scripts/selfcheck.sh`
Expected: FAIL at compile time, `cannot find 'AgentHookPayload' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Replace `boringNotch/managers/AgentSessionState.swift` entirely:

```swift
//
//  AgentSessionState.swift
//  boringNotch
//
//  Pure agent-session logic. Foundation only, so Scripts/selfcheck.sh can compile
//  this file standalone. Do not import Defaults, SwiftUI or AppKit here.
//

import Foundation

public enum AgentState: String, Equatable {
    case working
    case blocked
    case done
}

public struct AgentSession: Equatable {
    public var id: String
    public var tool: String
    public var state: AgentState
    public var message: String?
    public var cwd: String
    public var termProgram: String?
    public var tty: String?
    public var updatedAt: Date

    public init(id: String, tool: String, state: AgentState, message: String?,
                cwd: String, termProgram: String?, tty: String?, updatedAt: Date) {
        self.id = id
        self.tool = tool
        self.state = state
        self.message = message
        self.cwd = cwd
        self.termProgram = termProgram
        self.tty = tty
        self.updatedAt = updatedAt
    }

    /// Last path component of `cwd`, which is what the UI shows.
    public var projectName: String {
        (cwd as NSString).lastPathComponent
    }
}

public enum AgentHookResult: Equatable {
    case upsert(AgentSession)
    case end(id: String)
}

public enum AgentHookPayload {
    /// Parses one queue file: a space-separated header line written by bn-hook,
    /// followed by the agent's raw JSON hook payload.
    ///
    ///     claude vscode ttys004
    ///     {"session_id":"abc","cwd":"/x","hook_event_name":"Notification"}
    ///
    /// Returns nil when the input is not a usable payload. The caller deletes the
    /// file either way, so a malformed write cannot wedge the queue.
    public static func parse(_ raw: String, now: Date) -> AgentHookResult? {
        guard let newline = raw.firstIndex(of: "\n") else { return nil }
        let header = raw[raw.startIndex..<newline]
        let body = String(raw[raw.index(after: newline)...])

        let fields = header.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let tool = fields.first.map(unknownToNil) ?? nil
        let termProgram = fields.count > 1 ? unknownToNil(fields[1]) : nil
        let tty = fields.count > 2 ? unknownToNil(fields[2]) : nil

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["session_id"] as? String, !id.isEmpty
        else { return nil }

        let event = json["hook_event_name"] as? String ?? ""
        if event == "SessionEnd" { return .end(id: id) }

        return .upsert(AgentSession(
            id: id,
            tool: tool ?? "claude",
            state: state(for: event),
            message: json["message"] as? String,
            cwd: json["cwd"] as? String ?? "",
            termProgram: termProgram,
            tty: tty,
            updatedAt: now
        ))
    }

    /// Maps a hook event name to a session state. Unrecognised events degrade to
    /// `.working` rather than being dropped, so a renamed or newly added agent hook
    /// keeps the session visible instead of making it silently vanish.
    static func state(for event: String) -> AgentState {
        switch event {
        case "Notification": return .blocked
        case "Stop": return .done
        default: return .working
        }
    }

    /// bn-hook writes "?" when a value is not available in its environment.
    private static func unknownToNil(_ value: String) -> String? {
        value == "?" || value.isEmpty ? nil : value
    }
}

public enum AgentSessionReducer {
    /// Collapses N sessions into the single state the closed-notch dot shows.
    public static func worstState(_ sessions: [AgentSession]) -> AgentState? {
        if sessions.isEmpty { return nil }
        if sessions.contains(where: { $0.state == .blocked }) { return .blocked }
        if sessions.contains(where: { $0.state == .working }) { return .working }
        return .done
    }

    /// Drops sessions whose agent has stopped reporting, so a crashed process
    /// cannot leave a dot on screen indefinitely.
    public static func pruned(_ sessions: [AgentSession], now: Date,
                              staleAfter: TimeInterval) -> [AgentSession] {
        sessions.filter { now.timeIntervalSince($0.updatedAt) < staleAfter }
    }
}
```

- [ ] **Step 4: Run the checks to verify they pass**

Run: `./Scripts/selfcheck.sh`
Expected: `self-checks passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add boringNotch/managers/AgentSessionState.swift Scripts/selfcheck/main.swift
git commit -m "Add agent session model, hook payload parser and reducers"
```

---

### Task 3: Middle panel enum, migration, and Defaults keys

**Files:**
- Modify: `boringNotch/models/HomeMiddlePanel.swift` (currently the placeholder from Task 1)
- Modify: `boringNotch/models/Constants.swift:109` and `:71-114`
- Modify: `Scripts/selfcheck/main.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `HomeMiddlePanel` (`.none`, `.calendar`, `.agents`), `HomeMiddlePanelMigration.migrate(didMigrate:legacyShowCalendar:current:) -> (panel: HomeMiddlePanel, didMigrate: Bool)`, and these `Defaults.Keys`: `homeMiddlePanel`, `didMigrateCalendarPanel`, `showVPNDot`, `vpnIgnoredInterfaces`, `showVPNEgressIP`, `showAgentDot`, `agentAlertDuration`, `agentStaleTimeout`. Tasks 4, 6, 8, 9, 10 and 11 read these keys.

- [ ] **Step 1: Write the failing checks**

Append to `Scripts/selfcheck/main.swift`, before the final `print`:

```swift
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
```

- [ ] **Step 2: Run the checks to verify they fail**

Run: `./Scripts/selfcheck.sh`
Expected: FAIL at compile time, `cannot find 'HomeMiddlePanelMigration' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Replace `boringNotch/models/HomeMiddlePanel.swift` entirely:

```swift
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
```

- [ ] **Step 4: Run the checks to verify they pass**

Run: `./Scripts/selfcheck.sh`
Expected: `self-checks passed`, exit 0.

- [ ] **Step 5: Add the Defaults keys**

In `boringNotch/models/Constants.swift`, add this immediately above `extension Defaults.Keys {` (around line 71):

```swift
extension HomeMiddlePanel: Defaults.Serializable {}
```

Then add a new section at the end of the `extension Defaults.Keys` block, just before its closing brace:

```swift
    // MARK: Dev status
    /// Which panel occupies the middle slot of the open notch home view.
    /// Defaults to .agents for fresh installs; existing installs are migrated
    /// from the legacy showCalendar key on first launch.
    static let homeMiddlePanel = Key<HomeMiddlePanel>("homeMiddlePanel", default: .agents)
    static let didMigrateCalendarPanel = Key<Bool>("didMigrateCalendarPanel", default: false)

    static let showVPNDot = Key<Bool>("showVPNDot", default: true)
    /// Whole interface names to exclude, comma or space separated. iCloud Private
    /// Relay and an idle Tailscale daemon both create utun devices.
    static let vpnIgnoredInterfaces = Key<String>("vpnIgnoredInterfaces", default: "")
    /// Off by default: this makes an outbound request to a third party on every
    /// network change, so it is the user's call.
    static let showVPNEgressIP = Key<Bool>("showVPNEgressIP", default: false)

    static let showAgentDot = Key<Bool>("showAgentDot", default: true)
    static let agentAlertDuration = Key<Double>("agentAlertDuration", default: 4)
    static let agentStaleTimeout = Key<Double>("agentStaleTimeout", default: 1800)
```

Leave `showCalendar` at line 109 in place. It is now legacy-only, read once by the migration. Add a trailing comment to it:

```swift
    static let showCalendar = Key<Bool>("showCalendar", default: false) // legacy, migrated into homeMiddlePanel
```

- [ ] **Step 6: Run the migration at launch**

In `boringNotch/boringNotchApp.swift`, inside the app's existing startup path (the same place other one-time setup runs), add:

```swift
let migration = HomeMiddlePanelMigration.migrate(
    didMigrate: Defaults[.didMigrateCalendarPanel],
    legacyShowCalendar: Defaults[.showCalendar],
    current: Defaults[.homeMiddlePanel]
)
Defaults[.homeMiddlePanel] = migration.panel
Defaults[.didMigrateCalendarPanel] = migration.didMigrate
```

- [ ] **Step 7: Verify the project still builds**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

The project has two native targets, `boringNotch` (the app) and `BoringNotchXPCHelper`. There are no shared schemes, so Xcode autocreates one per target and `boringNotch` is the app scheme.

Note: the first build resolves SPM packages (SkyLightWindow, Pow, MacroVisionKit, swift-syntax, AsyncXPCConnection, LaunchAtLogin-Modern, lottie-spm, swift-collections) and takes several minutes. Later builds are fast.

- [ ] **Step 8: Commit**

```bash
git add boringNotch/models/HomeMiddlePanel.swift boringNotch/models/Constants.swift boringNotch/boringNotchApp.swift Scripts/selfcheck/main.swift
git commit -m "Add home middle panel enum, one-time migration and dev status defaults"
```

---

### Task 4: VPNStatusManager

**Files:**
- Create: `boringNotch/managers/VPNStatusManager.swift`

**Interfaces:**
- Consumes: `VPNClassifier.isVPN(interface:ignoring:)`, `VPNClassifier.parseIgnoreList(_:)` from Task 1; `Defaults[.vpnIgnoredInterfaces]`, `Defaults[.showVPNEgressIP]` from Task 3.
- Produces: `VPNStatusManager.shared` with published `primaryInterface: String`, `isTunneled: Bool`, `readFailed: Bool`, `egressIP: String?`. Tasks 8 and 11 read these.

- [ ] **Step 1: Write the implementation**

Create `boringNotch/managers/VPNStatusManager.swift`:

```swift
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
```

- [ ] **Step 2: Start the manager at launch**

In `boringNotch/boringNotchApp.swift`, in the same startup path used in Task 3 Step 6, add:

```swift
_ = VPNStatusManager.shared
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify the sandboxed read works (this is the plan's main technical risk)**

Temporarily add to `refresh()`, right after the `interface` assignment:

```swift
NSLog("VPN: primaryInterface=\(interface ?? "<nil>") tunneled=\(isTunneled)")
```

Run the app from Xcode. Read the console.

Expected: a real interface name such as `en0`.

**If it logs `<nil>`,** App Sandbox denied `SCDynamicStoreCopyValue`. Do Task 5. **If it logs an interface name, skip Task 5 entirely.**

Then connect a VPN and confirm the log flips to a `utun*` name, and that `tunneled=true`. Remove the `NSLog` afterwards.

- [ ] **Step 5: Commit**

```bash
git add boringNotch/managers/VPNStatusManager.swift boringNotch/boringNotchApp.swift
git commit -m "Add VPN status manager reading the default route interface"
```

---

### Task 5: CONDITIONAL - move the primary-interface read into the XPC helper

**Do this task only if Task 4 Step 4 logged `<nil>`.** If it logged an interface name, skip to Task 6.

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Modify: `boringNotch/managers/VPNStatusManager.swift`

**Interfaces:**
- Consumes: `VPNStatusManager` from Task 4.
- Produces: `XPCHelperClient.shared.currentPrimaryInterface() async -> String?`.

- [ ] **Step 1: Add the protocol method to BOTH copies**

The two `BoringNotchXPCHelperProtocol.swift` files must declare identical protocols or the XPC connection fails at runtime. Add to both:

```swift
    // Primary network interface (performed by the helper, App Sandbox blocks it in-app)
    func currentPrimaryInterface(with reply: @escaping (String?) -> Void)
```

- [ ] **Step 2: Implement it in the helper**

In `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`, add `import SystemConfiguration` at the top and this method to the class:

```swift
    @objc func currentPrimaryInterface(with reply: @escaping (String?) -> Void) {
        guard let store = SCDynamicStoreCreate(nil, "boringNotch.vpn" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString),
              let dict = value as? [String: Any],
              let interface = dict["PrimaryInterface"] as? String
        else {
            reply(nil)
            return
        }
        reply(interface)
    }
```

- [ ] **Step 3: Add the client wrapper**

In `boringNotch/XPCHelperClient/XPCHelperClient.swift`, following the pattern already used by the existing brightness wrappers in that file:

```swift
    @MainActor
    func currentPrimaryInterface() async -> String? {
        let service = ensureRemoteService()
        return try? await service.withValueErrorCompletion { proxy, handler in
            proxy.currentPrimaryInterface(with: handler)
        }
    }
```

Match the exact `AsyncXPCConnection` call style used by `currentScreenBrightness` in the same file. Read it first and copy its shape.

- [ ] **Step 4: Switch the manager to the helper**

In `VPNStatusManager.swift`, replace the body of `refresh()` with an async version and delete the static `readPrimaryInterface()`:

```swift
    func refresh() {
        Task { @MainActor in
            let interface = await XPCHelperClient.shared.currentPrimaryInterface()
            readFailed = interface == nil
            primaryInterface = interface ?? ""
            isTunneled = VPNClassifier.isVPN(
                interface: primaryInterface,
                ignoring: VPNClassifier.parseIgnoreList(Defaults[.vpnIgnoredInterfaces])
            )
            refreshEgressIP()
        }
    }
```

Remove the now-unused `import SystemConfiguration` from the manager.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

Re-add the `NSLog` from Task 4 Step 4, run from Xcode, confirm a real interface name appears, then remove it.

- [ ] **Step 6: Commit**

```bash
git add BoringNotchXPCHelper boringNotch/XPCHelperClient boringNotch/managers/VPNStatusManager.swift
git commit -m "Read primary network interface via the XPC helper"
```

---

### Task 6: AgentSessionManager and the hook script

**Files:**
- Create: `boringNotch/managers/AgentSessionManager.swift`

**Interfaces:**
- Consumes: `AgentHookPayload.parse(_:now:)`, `AgentHookResult`, `AgentSession`, `AgentSessionReducer` from Task 2; `Defaults[.agentStaleTimeout]` from Task 3.
- Produces: `AgentSessionManager.shared` with published `sessions: [AgentSession]` and `pendingAlert: AgentSession?`, plus `hookScriptPath: String`, `hookConfigSnippet: String`, and `dismissAlert()`. Tasks 8, 9, 10 and 11 use these.

- [ ] **Step 1: Write the implementation**

Create `boringNotch/managers/AgentSessionManager.swift`:

```swift
//
//  AgentSessionManager.swift
//  boringNotch
//
//  Watches a directory inside the app container that coding agents write into
//  via a shell hook. The directory is an EVENT QUEUE, not a state store: every
//  hook invocation is a separate process writing its own file, so files are
//  consumed into memory and then deleted. Nothing accumulates on disk.
//

import Combine
import Defaults
import Foundation

@MainActor
final class AgentSessionManager: ObservableObject {
    static let shared = AgentSessionManager()

    @Published private(set) var sessions: [AgentSession] = []
    /// Set when a session newly enters .blocked. The closed notch preempts on this
    /// and clears it via dismissAlert() once the alert has been shown.
    @Published var pendingAlert: AgentSession?

    private var source: DispatchSourceFileSystemObject?
    private var directoryFD: CInt = -1
    private var pruneTimer: Timer?

    // MARK: - Paths
    //
    // Inside the sandbox, .applicationSupportDirectory resolves to
    // ~/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support

    static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoringNotch", isDirectory: true)
    }

    static var queueDirectory: URL {
        supportDirectory.appendingPathComponent("agents", isDirectory: true)
    }

    static var hookScriptURL: URL {
        supportDirectory.appendingPathComponent("bn-hook")
    }

    var hookScriptPath: String { Self.hookScriptURL.path }

    // MARK: - The hook script
    //
    // Deliberately parses no JSON. jq and python3 are not guaranteed to exist, and
    // a hook that fails takes the whole feature down. Line 1 is a header the shell
    // can produce with no tooling; the rest is the agent's raw payload, which the
    // app parses. The mv is atomic within one filesystem, so the watcher never
    // reads a half-written file.
    //
    // The tty comes from the PARENT process, not from `tty`. Claude Code hands the
    // hook its JSON on stdin, so stdin is a pipe and `tty` would report "not a tty".

    static let hookScript = """
    #!/bin/sh
    d="$HOME/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support/BoringNotch/agents"
    mkdir -p "$d"
    { echo "${1:-claude} ${TERM_PROGRAM:-?} $(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ' || echo '?')"
      cat; } > "$d/.tmp.$$" && mv "$d/.tmp.$$" "$d/$$.json"

    """

    /// The block the user pastes into ~/.claude/settings.json.
    var hookConfigSnippet: String {
        let path = hookScriptPath
        return """
        {
          "hooks": {
            "Notification": [
              { "hooks": [{ "type": "command", "command": "'\(path)' claude" }] }
            ],
            "Stop": [
              { "hooks": [{ "type": "command", "command": "'\(path)' claude" }] }
            ],
            "SessionEnd": [
              { "hooks": [{ "type": "command", "command": "'\(path)' claude" }] }
            ]
          }
        }
        """
    }

    // MARK: - Lifecycle

    private init() {
        installHookScript()
        startWatching()
        drain()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.prune() }
        }
    }

    deinit {
        source?.cancel()
        pruneTimer?.invalidate()
    }

    /// Written on every launch rather than only when missing, so the script cannot
    /// drift out of sync with the parser above after an app update.
    private func installHookScript() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.queueDirectory, withIntermediateDirectories: true)
            try Self.hookScript.write(to: Self.hookScriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755],
                                 ofItemAtPath: Self.hookScriptURL.path)
        } catch {
            NSLog("AgentSessionManager: could not install hook script: \(error)")
        }
    }

    private func startWatching() {
        directoryFD = open(Self.queueDirectory.path, O_EVTONLY)
        guard directoryFD >= 0 else {
            NSLog("AgentSessionManager: could not open queue directory")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.drain() }
        }
        let fd = directoryFD
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    // MARK: - Draining

    /// Reads every queued file in write order, folds it into the in-memory session
    /// map, then deletes it. Called on launch too, so events that arrived while the
    /// app was not running are not lost.
    func drain() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.queueDirectory.path)
        else { return }

        let now = Date()
        var byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let previousStates = byID.mapValues(\.state)

        let queued = names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".tmp.") }
            .map { Self.queueDirectory.appendingPathComponent($0) }
            .sorted { Self.modified($0) < Self.modified($1) }

        for url in queued {
            if let raw = try? String(contentsOf: url, encoding: .utf8),
               let result = AgentHookPayload.parse(raw, now: now) {
                switch result {
                case .upsert(let session): byID[session.id] = session
                case .end(let id): byID.removeValue(forKey: id)
                }
            }
            // Deleted whether or not it parsed, so a malformed write cannot wedge
            // the queue and be re-read on every subsequent event.
            try? fm.removeItem(at: url)
        }

        // A hook killed mid-write leaves a .tmp file behind.
        for name in names where name.hasPrefix(".tmp.") {
            let url = Self.queueDirectory.appendingPathComponent(name)
            if now.timeIntervalSince(Self.modified(url)) > 60 {
                try? fm.removeItem(at: url)
            }
        }

        let updated = AgentSessionReducer.pruned(
            Array(byID.values), now: now, staleAfter: Defaults[.agentStaleTimeout])
        sessions = updated.sorted { $0.updatedAt > $1.updatedAt }

        // Fire the alert only on a transition INTO blocked, not on every redraw of
        // an already-blocked session.
        if let newlyBlocked = sessions.first(where: {
            $0.state == .blocked && previousStates[$0.id] != .blocked
        }) {
            pendingAlert = newlyBlocked
        }
    }

    func dismissAlert() {
        pendingAlert = nil
    }

    private func prune() {
        sessions = AgentSessionReducer.pruned(
            sessions, now: Date(), staleAfter: Defaults[.agentStaleTimeout])
    }

    private static func modified(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            .flatMap { $0 } ?? .distantPast
    }
}
```

- [ ] **Step 2: Start the manager at launch**

In `boringNotch/boringNotchApp.swift`, alongside the `VPNStatusManager.shared` line from Task 4:

```swift
_ = AgentSessionManager.shared
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify the hook round-trip end to end**

Run the app once so the script is installed, then from a terminal:

```bash
D="$HOME/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support/BoringNotch"
ls -l "$D/bn-hook"
echo '{"session_id":"test1","cwd":"/Users/me/demo","hook_event_name":"Notification","message":"needs approval"}' | "$D/bn-hook" claude
sleep 1
ls "$D/agents"
```

Expected: `bn-hook` exists and is mode `755`. After the pipe, `$D/agents` is **empty**, because the app consumed and deleted the file. If a `.json` file is still sitting there, the watcher is not running: check the console for "could not open queue directory".

Add a temporary `NSLog("sessions=\(sessions.map { "\($0.id):\($0.state)" })")` at the end of `drain()` to confirm `test1:blocked` appears, then remove it.

- [ ] **Step 5: Commit**

```bash
git add boringNotch/managers/AgentSessionManager.swift boringNotch/boringNotchApp.swift
git commit -m "Add agent session manager with hook script and queue watcher"
```

---

### Task 7: Click-to-focus via the XPC helper

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Create: `boringNotch/helpers/SessionFocus.swift`

**Interfaces:**
- Consumes: `AgentSession` (`termProgram`, `cwd`, `tty`, `projectName`) from Task 2.
- Produces: `SessionFocus.focus(_ session: AgentSession)`. Tasks 9 and 10 call this.

The split is deliberate: the sandboxed app is allowed to enumerate and activate running applications, but not to use the Accessibility API. The helper is unsandboxed and already holds AX authorization. So the app resolves and activates the process, and passes only a pid to the helper for the window raise. This also avoids adding anything to `com.apple.security.temporary-exception.apple-events`, which currently lists only Spotify and Music.

- [ ] **Step 1: Add the protocol method to BOTH copies**

Both `BoringNotchXPCHelperProtocol.swift` files must declare identical protocols or the XPC connection fails at runtime. Add to both:

```swift
    // Raise a specific window of an already-running app (requires Accessibility)
    func focusWindow(_ pid: Int32, titleFragment: String, with reply: @escaping (Bool) -> Void)
```

- [ ] **Step 2: Implement it in the helper**

In `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`, add this method to the class (`ApplicationServices` is already imported):

```swift
    @objc func focusWindow(_ pid: Int32, titleFragment: String,
                           with reply: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted() else {
            reply(false)
            return
        }
        let axApp = AXUIElementCreateApplication(pid_t(pid))
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            reply(false)
            return
        }

        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                    window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String,
                  !titleFragment.isEmpty,
                  title.contains(titleFragment)
            else { continue }

            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                axApp, kAXFocusedWindowAttribute as CFString, window)
            reply(true)
            return
        }
        reply(false)
    }
```

- [ ] **Step 3: Add the client wrapper**

In `boringNotch/XPCHelperClient/XPCHelperClient.swift`, matching the call style of the existing brightness wrappers in that file:

```swift
    @MainActor
    func focusWindow(pid: Int32, titleFragment: String) async -> Bool {
        let service = ensureRemoteService()
        let result = try? await service.withValueErrorCompletion { proxy, handler in
            proxy.focusWindow(pid, titleFragment: titleFragment, with: handler)
        }
        return result ?? false
    }
```

Read `currentScreenBrightness` in that file first and copy its exact shape.

- [ ] **Step 4: Write the app-side resolver**

Create `boringNotch/helpers/SessionFocus.swift`:

```swift
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
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add BoringNotchXPCHelper boringNotch/XPCHelperClient boringNotch/helpers/SessionFocus.swift
git commit -m "Add click-to-focus for agent sessions via the XPC helper"
```

---

### Task 8: Closed-notch status dots

**Files:**
- Create: `boringNotch/components/Notch/StatusDots.swift`
- Modify: `boringNotch/ContentView.swift:61-81` (`computedChinWidth`), `:91-104` (the `mainLayout` overlay chain)

**Interfaces:**
- Consumes: `VPNStatusManager.shared.isTunneled` from Task 4; `AgentSessionManager.shared.sessions` and `AgentSessionReducer.worstState(_:)` from Tasks 2 and 6; `Defaults[.showVPNDot]`, `Defaults[.showAgentDot]` from Task 3.
- Produces: `StatusDotsOverlay` view and `StatusDots.anyActive` (a `Bool` used by `computedChinWidth`).

- [ ] **Step 1: Write the dots view**

Create `boringNotch/components/Notch/StatusDots.swift`:

```swift
//
//  StatusDots.swift
//  boringNotch
//
//  Two dots pinned to the outer edges of the closed notch. They are an OVERLAY,
//  deliberately outside the live-activity else-if chain in ContentView, so they
//  coexist with music, HUD and battery instead of competing for the same slot.
//

import Defaults
import SwiftUI

enum StatusDots {
    static let stripWidth: CGFloat = 10

    /// Whether either dot currently wants space. ContentView widens the closed
    /// notch by 2 * stripWidth when this is true.
    @MainActor
    static var anyActive: Bool {
        vpnActive || agentState != nil
    }

    @MainActor
    static var vpnActive: Bool {
        Defaults[.showVPNDot] && VPNStatusManager.shared.isTunneled
    }

    @MainActor
    static var agentState: AgentState? {
        guard Defaults[.showAgentDot] else { return nil }
        return AgentSessionReducer.worstState(AgentSessionManager.shared.sessions)
    }
}

struct StatusDotsOverlay: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var vpn = VPNStatusManager.shared
    @ObservedObject private var agents = AgentSessionManager.shared
    @Default(.showVPNDot) private var showVPNDot
    @Default(.showAgentDot) private var showAgentDot

    private var agentState: AgentState? {
        guard showAgentDot else { return nil }
        return AgentSessionReducer.worstState(agents.sessions)
    }

    var body: some View {
        HStack(spacing: 0) {
            dot(color: .green, visible: showVPNDot && vpn.isTunneled, pulsing: false)
                .frame(width: StatusDots.stripWidth)
            Spacer(minLength: 0)
            dot(color: agentColor,
                visible: agentState != nil,
                pulsing: agentState == .blocked)
                .frame(width: StatusDots.stripWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .allowsHitTesting(false)
    }

    private var agentColor: Color {
        switch agentState {
        case .blocked: return .orange
        case .working: return .blue
        case .done: return .green
        case nil: return .clear
        }
    }

    @ViewBuilder
    private func dot(color: Color, visible: Bool, pulsing: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(visible ? 1 : 0)
            .modifier(PulseModifier(active: pulsing))
            .animation(.smooth, value: visible)
    }
}

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (on ? 0.35 : 1.0) : 1.0)
            .animation(active ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                              : .default,
                       value: on)
            .onAppear { if active { on = true } }
            .onChange(of: active) { _, isActive in on = isActive }
    }
}
```

- [ ] **Step 2: Reserve the edge strips in the chin width**

In `boringNotch/ContentView.swift`, in `computedChinWidth` (line 61), add this immediately before `return chinWidth`:

```swift
        if StatusDots.anyActive {
            chinWidth += 2 * StatusDots.stripWidth
        }
```

- [ ] **Step 3: Overlay the dots on the notch shape**

In `boringNotch/ContentView.swift`, in the `mainLayout` modifier chain, add a new overlay directly after the existing `.overlay(alignment: .top) { ... }` block that draws the 1pt black rectangle (around line 105-110):

```swift
                    .overlay(alignment: .top) {
                        if vm.notchState == .closed {
                            StatusDotsOverlay()
                                .padding(.horizontal, 4)
                        }
                    }
```

- [ ] **Step 4: Build and verify visually**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

Run the app and confirm:
- With a VPN connected, a green dot sits at the leading edge of the closed notch.
- Playing music, the dot and the album art are both visible and do not overlap.
- Injecting a blocked session (Task 6 Step 4's command) shows a pulsing orange dot at the trailing edge.

- [ ] **Step 5: Commit**

```bash
git add boringNotch/components/Notch/StatusDots.swift boringNotch/ContentView.swift
git commit -m "Add VPN and agent status dots to the closed notch"
```

---

### Task 9: The blocked-agent alert

**Files:**
- Create: `boringNotch/components/Live activities/AgentAlertView.swift`
- Modify: `boringNotch/ContentView.swift:260-301` (the live-activity chain), `:61-81` (`computedChinWidth`)

**Interfaces:**
- Consumes: `AgentSessionManager.shared.pendingAlert` and `dismissAlert()` from Task 6; `SessionFocus.focus(_:)` from Task 7; `Defaults[.agentAlertDuration]` from Task 3.
- Produces: `AgentAlertView`.

- [ ] **Step 1: Write the alert view**

Create `boringNotch/components/Live activities/AgentAlertView.swift`:

```swift
//
//  AgentAlertView.swift
//  boringNotch
//
//  Structurally the same as the battery notification branch it sits below:
//  content, a black spacer the width of the physical notch, then content.
//

import SwiftUI

struct AgentAlertView: View {
    @EnvironmentObject var vm: BoringViewModel
    let session: AgentSession

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(session.projectName)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(session.message ?? "needs your attention")
                .font(.caption)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 140, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            SessionFocus.focus(session)
            AgentSessionManager.shared.dismissAlert()
        }
    }
}
```

- [ ] **Step 2: Add the branch to the live-activity chain**

In `boringNotch/ContentView.swift`, add `@ObservedObject var agents = AgentSessionManager.shared` alongside the other `@ObservedObject` properties at the top of `ContentView` (near line 21-25).

Then in `NotchLayout()`, insert a new branch **directly after** the battery-notification `if` block and **before** the `else if coordinator.sneakPeek.show && Defaults[.inlineHUD]` branch (around line 287):

```swift
                      } else if let alert = agents.pendingAlert, vm.notchState == .closed, !vm.hideOnClosed {
                          AgentAlertView(session: alert)
                              .transition(.opacity)
                              .task(id: alert.id) {
                                  try? await Task.sleep(for: .seconds(Defaults[.agentAlertDuration]))
                                  guard !Task.isCancelled else { return }
                                  agents.dismissAlert()
                              }
```

- [ ] **Step 3: Widen the notch while the alert is up**

In `computedChinWidth`, add this as the first condition in the chain, before the existing battery condition:

```swift
        if coordinator.expandingView.show == false,
           AgentSessionManager.shared.pendingAlert != nil,
           vm.notchState == .closed, !vm.hideOnClosed {
            return 640
        }
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

Run the app, then trigger a blocked session:

```bash
D="$HOME/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support/BoringNotch"
echo '{"session_id":"t2","cwd":"'"$PWD"'","hook_event_name":"Notification","message":"needs approval"}' | "$D/bn-hook" claude
```

Expected: the notch expands showing the project name and message, collapses after ~4 seconds, and leaves a pulsing orange dot.

- [ ] **Step 5: Commit**

```bash
git add "boringNotch/components/Live activities/AgentAlertView.swift" boringNotch/ContentView.swift
git commit -m "Add preempting alert when an agent becomes blocked"
```

---

### Task 10: The open-notch middle slot

**Files:**
- Create: `boringNotch/components/Agents/AgentPanelView.swift`
- Modify: `boringNotch/components/Notch/NotchHomeView.swift:232,438-466`

**Interfaces:**
- Consumes: `AgentSessionManager.shared.sessions` from Task 6; `SessionFocus.focus(_:)` from Task 7; `Defaults[.homeMiddlePanel]` and `HomeMiddlePanel` from Task 3.
- Produces: `AgentPanelView`.

- [ ] **Step 1: Write the panel**

Create `boringNotch/components/Agents/AgentPanelView.swift`:

```swift
//
//  AgentPanelView.swift
//  boringNotch
//

import SwiftUI

struct AgentPanelView: View {
    @ObservedObject private var agents = AgentSessionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agents")
                .font(.caption)
                .foregroundStyle(.gray)

            if agents.sessions.isEmpty {
                // An explicit empty state, not a collapse. If this view vanished
                // whenever no agent was running, the whole HStack would reflow
                // every time a session started or stopped.
                Spacer()
                Text("No active sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(agents.sessions, id: \.id) { session in
                            row(session)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func row(_ session: AgentSession) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: session.state))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let message = session.message, session.state == .blocked {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { SessionFocus.focus(session) }
    }

    private func color(for state: AgentState) -> Color {
        switch state {
        case .blocked: return .orange
        case .working: return .blue
        case .done: return .green
        }
    }
}
```

- [ ] **Step 2: Switch the middle slot**

In `boringNotch/components/Notch/NotchHomeView.swift`, replace `mainContent` (lines 442-466) with:

```swift
    private var mainContent: some View {
        HStack(alignment: .top,
               spacing: (shouldShowCamera && Defaults[.homeMiddlePanel] != .none) ? 10 : 15) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)

            switch Defaults[.homeMiddlePanel] {
            case .none:
                EmptyView()
            case .calendar:
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            case .agents:
                AgentPanelView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
```

- [ ] **Step 3: Update the edge-hiding condition**

In the same file at line 232, replace:

```swift
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
```

with:

```swift
        let shouldHideEdges = Defaults[.homeMiddlePanel] != .none && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

Run the app, open the notch. Expected: the agent panel occupies the middle slot showing "No active sessions". Inject a session with the Task 9 Step 4 command and confirm a row appears. Click it and confirm your editor window for that directory is raised.

- [ ] **Step 5: Commit**

```bash
git add boringNotch/components/Agents/AgentPanelView.swift boringNotch/components/Notch/NotchHomeView.swift
git commit -m "Give the home middle slot to the agent panel via the panel enum"
```

---

### Task 11: Settings

**Files:**
- Create: `boringNotch/components/Settings/DevStatusSettings.swift`
- Modify: `boringNotch/components/Settings/SettingsView.swift:39-41`, `:80-81`, `:712`, `:717-721`, `:765`, `:801`

**Interfaces:**
- Consumes: everything from Tasks 3, 4 and 6.
- Produces: `DevStatusSettings` view.

- [ ] **Step 1: Write the settings pane**

Create `boringNotch/components/Settings/DevStatusSettings.swift`:

```swift
//
//  DevStatusSettings.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct DevStatusSettings: View {
    @ObservedObject private var vpn = VPNStatusManager.shared
    @Default(.vpnIgnoredInterfaces) private var ignoredInterfaces
    @Default(.agentAlertDuration) private var alertDuration
    @Default(.agentStaleTimeout) private var staleTimeout
    @State private var copied = false

    var body: some View {
        Form {
            Section(header: Text("Home middle panel")) {
                Picker("Middle panel", selection: Defaults.binding(for: .homeMiddlePanel)) {
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
                Button(copied ? "Copied" : "Copy hook config") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        AgentSessionManager.shared.hookConfigSnippet, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Dev Status")
    }
}
```

- [ ] **Step 2: Register the pane in the sidebar**

In `boringNotch/components/Settings/SettingsView.swift`, add after the `Calendar` `NavigationLink` (line 39-41):

```swift
                NavigationLink(value: "Dev Status") {
                    Label("Dev Status", systemImage: "shield.lefthalf.filled")
                }
```

And add to the detail `switch` after `case "Calendar":` (line 80-81):

```swift
                case "Dev Status":
                    DevStatusSettings()
```

- [ ] **Step 3: Replace the calendar toggle with the picker**

In `CalendarSettings` (line 710), replace the `showCalendar` property (line 712):

```swift
    @Default(.homeMiddlePanel) var homeMiddlePanel: HomeMiddlePanel
```

Replace the `Defaults.Toggle(key: .showCalendar)` block (lines 719-721) with:

```swift
            Picker("Middle panel", selection: $homeMiddlePanel) {
                ForEach(HomeMiddlePanel.allCases) { panel in
                    Text(panel.displayName).tag(panel)
                }
            }
```

Replace both `.disabled(!showCalendar)` modifiers (lines 765 and 801) with:

```swift
                            .disabled(homeMiddlePanel != .calendar)
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
Expected: BUILD SUCCEEDED.

Open Settings. Verify:
- The Dev Status pane lists your real primary interface, matching `route -n get default | grep interface` in a terminal.
- Setting the middle panel to Calendar in either pane updates the other, since both bind the same key.
- "Copy hook config" puts valid JSON on the clipboard whose path matches the `bn-hook` file on disk.

- [ ] **Step 5: Wire up the real hook and confirm end to end**

Paste the copied config into `~/.claude/settings.json` (merge it with any existing keys). Start a Claude Code session in a project and let it hit a permission prompt.

Expected: the notch preempts with the project name, then leaves a pulsing orange dot. Clicking the alert raises the VS Code window for that project.

- [ ] **Step 6: Commit and push**

```bash
git add boringNotch/components/Settings
git commit -m "Add dev status settings pane and middle panel picker"
git push
```

---

## Self-Review

**Spec coverage.** Every section of `docs/superpowers/specs/2026-08-06-dev-status-notch-design.md` maps to a task:

| Spec section | Task |
| --- | --- |
| VPN detection, `isVPN` pure function | 1, 4 |
| VPN calibration knob (live readout, ignore list) | 4, 11 |
| Egress IP, opt-in | 4, 11 |
| Sandbox fallback to the helper | 5 (conditional) |
| Hook transport, `bn-hook`, line-1 header | 6 |
| Payload interpretation table, unknown events degrade | 2 |
| Session model, watcher, queue-not-store, pruning | 2, 6 |
| Focus the session, VS Code AX path, helper split | 7 |
| Edge strips, dots, coexistence with music | 8 |
| Blocked alert preempting the chain | 9 |
| Middle slot enum, migration, calendar not deleted | 3, 10, 11 |
| Settings table | 3, 11 |
| Testing without a test target | 1, 2, 3 |
| Manual verification checklist (7 items) | 4.4, 6.4, 8.4, 9.4, 10.4, 11.4, 11.5 |

**Placeholder scan.** No TBD/TODO/"handle edge cases" steps. Every code step has a full code block. Task 5 is conditional but its gate is a concrete observed value (`<nil>` in the console), not a judgement call.

**Type consistency.** Checked across tasks: `AgentSession` field names (`id`, `tool`, `state`, `message`, `cwd`, `termProgram`, `tty`, `updatedAt`) and `projectName` are used identically in Tasks 2, 6, 7, 9, 10. `AgentSessionReducer.worstState` / `.pruned` names match between Task 2's definition and Tasks 6 and 8's use. `AgentHookResult` cases `.upsert` / `.end` match between Tasks 2 and 6. `HomeMiddlePanel` cases and `displayName` match between Tasks 3, 10 and 11. `StatusDots.stripWidth` is defined in Task 8 and used only there. `XPCHelperClient.focusWindow(pid:titleFragment:)` matches between Tasks 7 Step 3 and 7 Step 4.

**Known soft spots, called out rather than hidden:**
- The `AsyncXPCConnection` call style in Tasks 5 and 7 is written from the shape of the existing brightness wrappers. Both steps instruct the implementer to read `currentScreenBrightness` first and match it exactly, because that API's exact generic signature was not verified.
- The three Claude Code hook event names (`Notification`, `Stop`, `SessionEnd`) should be confirmed against the current `/hooks` documentation at Task 11 Step 5. Only the settings snippet in Task 6 and the mapping in `AgentHookPayload.state(for:)` depend on them.

**Verified while planning, not assumed:**
- The `swiftc` check harness was built and run before this plan was written. It compiles multiple Foundation-only files against a `main.swift` of `precondition` calls and returns a real pass/fail exit code.
- Targets are `boringNotch` and `BoringNotchXPCHelper`, read from `project.pbxproj`. No shared schemes exist, so `boringNotch` is the autocreated app scheme.
- Swift 6.3.3, target `arm64-apple-macosx26.0`.
- The app container already exists at `~/Library/Containers/theboringteam.boringnotch`, so `.applicationSupportDirectory` resolves inside it as the hook script's path assumes.
