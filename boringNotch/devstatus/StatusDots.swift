//
//  StatusDots.swift
//  boringNotch
//
//  Indicators pinned to the outer edges of the closed notch: keep-awake full moon and
//  VPN dot on the left, agent dot on the right. They are an OVERLAY,
//  deliberately outside the live-activity else-if chain in ContentView, so they
//  coexist with music, HUD and battery instead of competing for the same slot.
//

import Defaults
import SwiftUI

enum StatusDots {
    /// Width of one indicator slot. A strip holds one slot per visible indicator.
    static let slotWidth: CGFloat = 10

    /// Width of each side strip. Both strips share it so the notch stays centred:
    /// the left side carries the keep-awake glyph and the VPN dot, the right side
    /// the agent dot, and the wider side sets the width.
    @MainActor
    static var stripWidth: CGFloat {
        let left = (keepAwakeVisible ? 1 : 0) + (vpnActive ? 1 : 0)
        let right = agentState != nil ? 1 : 0
        return slotWidth * CGFloat(max(left, right))
    }

    /// Whether any indicator currently wants space. ContentView widens the closed
    /// notch by 2 * stripWidth when this is true.
    @MainActor
    static var anyActive: Bool {
        stripWidth > 0
    }

    @MainActor
    static var keepAwakeVisible: Bool {
        Defaults[.showKeepAwakeGlyph] && KeepAwakeManager.shared.isActive
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
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @Default(.showVPNDot) private var showVPNDot
    @Default(.showKeepAwakeGlyph) private var showKeepAwakeGlyph
    @Default(.showAgentDot) private var showAgentDot

    private var agentState: AgentState? {
        guard showAgentDot else { return nil }
        return AgentSessionReducer.worstState(agents.sessions)
    }

    var body: some View {
        let width = StatusDots.stripWidth
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if showKeepAwakeGlyph && keepAwake.isActive {
                    KeepAwakeMoon()
                        .frame(width: 7, height: 7)
                        .frame(width: StatusDots.slotWidth)
                        .transition(.opacity)
                }
                if showVPNDot && vpn.isTunneled {
                    dot(color: .blue, visible: true, pulsing: false)
                        .frame(width: StatusDots.slotWidth)
                        .transition(.opacity)
                }
            }
            .frame(width: width)
            Spacer(minLength: 0)
            dot(color: agentColor,
                visible: agentState != nil,
                pulsing: agentState == .blocked)
                .frame(width: StatusDots.slotWidth)
                .frame(width: width, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .animation(.smooth, value: keepAwake.isActive)
        .animation(.smooth, value: vpn.isTunneled)
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
