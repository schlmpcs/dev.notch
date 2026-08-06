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

    /// Written only when the on-disk content differs from the current source, so the
    /// script still cannot drift out of sync with the parser above after an app
    /// update, but a launch that changes nothing does not rewrite the file. A rewrite
    /// replaces the file (new inode) and macOS re-quarantines any file a sandboxed app
    /// writes, so a user who ran `xattr -d com.apple.quarantine` once would otherwise
    /// have to redo that after every single launch.
    private func installHookScript() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.queueDirectory, withIntermediateDirectories: true)
            let existing = try? String(contentsOf: Self.hookScriptURL, encoding: .utf8)
            guard existing != Self.hookScript else { return }
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
