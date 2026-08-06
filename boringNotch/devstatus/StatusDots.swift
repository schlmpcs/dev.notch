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
