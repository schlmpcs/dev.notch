# Dev Status in the Notch: VPN state and coding-agent attention

Date: 2026-08-06
Status: approved, ready for planning

## Goal

Two glanceable signals in the closed notch for a developer who runs coding agents
locally and works behind a VPN:

1. Is my traffic tunneled right now?
2. Does a coding agent need my attention, and can I get to it in one click?

Both are peripheral-vision features. Neither may hide or displace anything the notch
already shows.

## Non-goals

- Remote agents reporting over the network. Local only. See "Deferred" below.
- Per-vendor VPN integration (Tailscale peers, Mullvad server names, exit-node UI).
- SSH session listing or a quick-connect launcher.
- Long-running job progress bars.

## Constraints discovered

- The main app is sandboxed (`boringNotch/boringNotch.entitlements`,
  `com.apple.security.app-sandbox = true`). No arbitrary home-directory reads,
  no process enumeration.
- An unsandboxed XPC helper already exists and is already trusted for Accessibility
  (`BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements`,
  `com.apple.security.app-sandbox = false`). This is the escape hatch for anything
  local the sandbox blocks.
- The closed notch renders exactly one live activity, chosen by an `else if` chain in
  `ContentView.swift:260-301`: battery, then inline HUD, then music, then face, then
  empty.
- The open notch has two tabs (`boringNotch/enums/generic.swift:27`,
  `boringNotch/components/Tabs/TabSelectionView.swift:17`).
- App bundle identifier is `theboringteam.boringnotch`. Its data container is
  `~/Library/Containers/theboringteam.boringnotch/Data/`.
- The repository has no test target. All 8 targets are the app or the XPC service.
- The user's terminal environment reports `TERM_PROGRAM=vscode` with an empty
  `TERM_SESSION_ID`. VS Code is the primary environment that must work.

## Feature 1: VPN status

### Detection

New file `boringNotch/managers/VPNStatusManager.swift`. A `@MainActor` singleton
`ObservableObject`, matching `BrightnessManager` / `VolumeManager` conventions.

Trigger: `NWPathMonitor` from the Network framework. It is event-driven, so there is
no polling timer and no idle battery cost.

On each path update, read the system's actual default route rather than inferring one:

```
SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
  -> dictionary -> "PrimaryInterface" -> e.g. "en0", "utun4"
```

This distinguishes "a tunnel interface exists" from "my traffic actually goes through
it", which is the question the user is asking.

Classification is a pure function so it can be checked without a running network:

```swift
func isVPN(interface: String, ignoring: Set<String>) -> Bool
```

Returns true when `interface` has a prefix in `{utun, ipsec, ppp, tun, tap}` and is not
in `ignoring`.

### Calibration knob

iCloud Private Relay and an idle Tailscale daemon both create `utun` devices. No blind
heuristic classifies those correctly for every user. Therefore:

- Settings displays the **live primary interface name** so the user can see exactly
  what was detected.
- Settings offers an **ignore list** of interface names, empty by default.

### Egress IP

Off by default. When enabled, a plain-text egress IP is fetched on interface change
using the existing `com.apple.security.network.client` entitlement. It renders in the
open notch only, never in the dot.

Rationale for the default: this is an outbound request to a third party from the user's
machine, correlated with network changes. It is the user's call, so it is opt-in.

### Sandbox risk and fallback

If App Sandbox denies `SCDynamicStoreCopyValue`, the call moves into
`BoringNotchXPCHelper` as one new protocol method:

```swift
func currentPrimaryInterface(with reply: @escaping (String?) -> Void)
```

The manager's public surface does not change. This is a fallback, not a redesign, and
it is the first thing to verify at implementation time.

## Feature 2: Coding-agent attention

### Transport

File-based, inside the app's own data container. No listening socket, no port.

Watched directory:

```
~/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support/BoringNotch/agents/
```

The hook script ships inside the app bundle at `Contents/Resources/bn-hook`, so there
is no install step and no file to copy. It performs no JSON parsing:

```sh
#!/bin/sh
d="$HOME/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support/BoringNotch/agents"
mkdir -p "$d"
{ echo "${1:-claude} ${TERM_PROGRAM:-?} $(ps -o tty= -p $PPID 2>/dev/null || echo '?')"
  cat; } > "$d/.tmp.$$" && mv "$d/.tmp.$$" "$d/$$.json"
```

Line 1 is a space-separated header the shell can produce without parsing anything
(`tool`, `TERM_PROGRAM`, `tty`). Everything after it is the hook's raw JSON payload,
which the app parses.

The tty comes from `ps -o tty= -p $PPID`, not from `tty`. Claude Code hands the hook its
JSON on stdin, so stdin is a pipe and `tty` would report "not a tty". The parent process
is the agent running in the terminal, and its tty is the one worth recording. `ps` is
part of the base system, so this adds no dependency.

Properties this buys:

- Zero external dependencies. `jq` and `python3` are not required, so the hook cannot
  break on a machine where they are missing.
- `mv` within one filesystem is atomic, so the watcher never reads a half-written file.
- `TERM_PROGRAM` and `tty` are captured at hook time, from the process that actually
  has them. Neither is recoverable later from the sandboxed app.
- The script is agnostic to which hook event fired. The app reads `hook_event_name`
  out of the payload. If Claude Code's hook event names differ from what the settings
  snippet assumes, only the snippet changes, never the Swift code.

The user wires it up once in `~/.claude/settings.json`, pointing the attention-relevant
hooks at that path. Settings provides a **Copy hook config** button that emits the
snippet with the absolute path already filled in.

### Payload interpretation

The app maps the payload's `hook_event_name` to a session state:

| `hook_event_name` | Resulting state |
| --- | --- |
| `Notification` | `.blocked` (carries the `message` field) |
| `Stop` | `.done` |
| `SessionEnd` | session removed |
| anything else | `.working` |

Unrecognized event names degrade to `.working` rather than being dropped, so a new or
renamed Claude Code hook still keeps the session visible instead of silently vanishing.

`tool` is not present in the payload. It comes from the first argument passed to
`bn-hook` in the settings snippet (`bn-hook claude`), defaulting to `claude` when the
argument is absent, and is written into the line-1 header. A future Codex or Cursor
integration reuses the same script with a different argument and no code change.

Verify at implementation time that these three event names match the current Claude
Code `/hooks` documentation. Only the settings snippet and this mapping table change if
they differ; no other code depends on the names.

### Session model and watcher

New file `boringNotch/managers/AgentSessionManager.swift`. A `@MainActor` singleton
`ObservableObject`.

```swift
struct AgentSession: Identifiable {
    let id: String          // session_id from the payload
    var tool: String        // "claude", "codex", ...
    var state: State        // .working, .blocked, .done
    var message: String?
    var cwd: String
    var termProgram: String?
    var tty: String?
    var updatedAt: Date
}
```

The directory is an **event queue, not a state store.** Each hook invocation is a
separate process, so each write lands in its own `$$.json` file. The manager holds the
session state in memory; the files are consumed and deleted.

Watching uses `DispatchSource.makeFileSystemObjectSource` on a file descriptor for the
directory, on `.write`. On each event the manager reads every `*.json` in mtime order,
merges each into the in-memory session keyed by `session_id`, then **deletes the file**.
This keeps the directory near-empty and makes accumulation impossible. Files beginning
with `.tmp.` are skipped, since they are mid-write.

The manager also drains the directory once at launch, so events that arrived while the
app was not running are not lost.

Pruning rules:
- A session-end payload removes the session immediately.
- Sessions not updated within a configurable staleness window (default 30 minutes) are
  dropped, so a crashed agent cannot pin a dot on forever.
- Orphaned `.tmp.*` files older than a minute are deleted during the same pass, which
  covers a hook killed mid-write.

The reducer that collapses N sessions into one displayed state is a pure function:

```swift
func worstState(_ sessions: [AgentSession]) -> AgentSession.State?
```

Precedence: `.blocked` > `.working` > `.done` > nil.

### Focus the session

Triggered by clicking the alert or a row in the open notch.

`TERM_SESSION_ID` is empty under VS Code, so there is no terminal-tab handle to target.
Resolution order:

1. `termProgram` is `vscode` (also Cursor): activate the app, then walk its `AXWindows`
   via Accessibility and `AXRaise` the window whose `AXTitle` contains
   `basename(cwd)`. Falls back to plain activation when no window matches.
2. `termProgram` is `iTerm.app` or `Apple_Terminal`: AppleScript, selecting the session
   whose tty matches the recorded `tty`.
3. Anything else: activate the mapped application, or do nothing if unmapped.

All of this executes inside `BoringNotchXPCHelper`, which is unsandboxed and already
holds Accessibility authorization. Consequences: no additions to
`com.apple.security.temporary-exception.apple-events` (currently Spotify and Music
only), and no per-terminal allowlist to maintain.

New helper protocol method:

```swift
func focusSession(termProgram: String?, cwd: String, tty: String?, with reply: @escaping (Bool) -> Void)
```

Case 1 is the only path required to work at launch. Cases 2 and 3 are small and
included, but VS Code is what gets verified.

## Feature 3: Display layer

### Edge strips

When any dot is active, the closed notch reserves a 10pt strip on each outer edge and
widens by 20pt total. This reuses the widening mechanism `computedChinWidth` already
implements for the music live activity (`ContentView.swift:61-81`), so dots occupy
their own space and can never collide with album art or HUD content.

- Leading dot: VPN. Green when tunneled, dimmed when not. Hidden entirely when the
  feature is off.
- Trailing dot: agent count, colored by `worstState`. The blocked state pulses.

Dots are an overlay on the notch shape, outside the `else if` chain, so they coexist
with whatever live activity is currently showing.

### Blocked alert

A session transitioning into `.blocked` preempts the live-activity chain for a
configurable duration (default 4 seconds), showing tool icon, `basename(cwd)`, and the
hook message. It then collapses back to the trailing dot.

This is a new branch in the chain at `ContentView.swift:260`, placed directly below the
battery-notification branch, and structurally identical to it.

### Open notch

A section inside `NotchHomeView`, rendered only when at least one session exists. One
row per session: tool icon, `basename(cwd)`, state, message, clickable to focus.

No new tab. `NotchViews` and `TabSelectionView` are untouched.

## Settings

One new `SettingsEnum` case, with a matching pane and `Defaults.Keys` entries in
`boringNotch/models/Constants.swift`:

| Setting | Default |
| --- | --- |
| Show VPN dot | on |
| Interfaces to ignore | empty |
| Show egress IP | off |
| Show agent dot | on |
| Blocked-alert duration | 4s |
| Session staleness timeout | 30 min |

Plus a read-only live readout of the detected primary interface, and the **Copy hook
config** button.

## Testing

The repository has no test target, and adding one means restructuring the Xcode
project for two pure functions. That trade is not worth it here.

Instead, `isVPN(interface:ignoring:)` and `worstState(_:)` get `#if DEBUG`
assert-based self-checks, driven from a `#Preview`. This matches how the codebase
already exercises views, and it fails loudly in debug builds if either function
regresses.

Upgrade path: if a unit test target is added later, both self-checks move over
unchanged.

Manual verification checklist for implementation:

1. `SCDynamicStoreCopyValue` returns a non-nil primary interface from the sandboxed
   app. If not, move it to the helper.
2. Toggling a VPN flips the leading dot, and the Settings readout shows the expected
   interface name.
3. A hook write lands in the watched directory and appears as a session within one
   second.
4. A blocked session preempts the notch, then collapses to a dot.
5. Clicking the alert raises the correct VS Code window for that `cwd`.
6. Music playback and the dots render simultaneously without overlap.
7. Killing an agent process leaves no dot after the staleness window.

## Deferred

- Remote agents over SSH. The chosen file transport is local-only. Adding an
  `NWListener` on 127.0.0.1 later would let remote agents report through
  `ssh -R PORT:localhost:PORT` using the same hook contract. The
  `com.apple.security.network.server` entitlement is already granted, so this stays
  cheap. Not built now because the user runs agents locally.
- Per-vendor VPN detail (Tailscale peers, named WireGuard tunnels).
- SSH session indicator and quick-connect list.
- Long-running job progress.
