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
