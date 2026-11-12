//
//  KeepAwakeMoon.swift
//  boringNotch
//
//  The "keeping the display awake" glyph: a lit full moon with soft shading, faint
//  craters and a gentle glow. Drawn rather than an SF Symbol because
//  moonphase.full.moon renders as a hollow ring in monochrome, not a lit disc.
//

import SwiftUI

struct KeepAwakeMoon: View {
    var body: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [.white, Color(white: 0.86)],
                        center: UnitPoint(x: 0.38, y: 0.35),
                        startRadius: 0,
                        endRadius: d * 0.62
                    ))
                crater(d, x: 0.62, y: 0.38, radius: 0.16)
                crater(d, x: 0.36, y: 0.64, radius: 0.12)
                crater(d, x: 0.66, y: 0.70, radius: 0.08)
            }
            .frame(width: d, height: d)
            .shadow(color: .white.opacity(0.55), radius: d * 0.22)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel("Keeping display awake")
    }

    private func crater(_ d: CGFloat, x: CGFloat, y: CGFloat, radius: CGFloat) -> some View {
        Circle()
            .fill(Color(white: 0.72).opacity(0.55))
            .frame(width: d * radius * 2, height: d * radius * 2)
            .position(x: d * x, y: d * y)
    }
}
