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
