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
