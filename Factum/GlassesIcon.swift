//
//  GlassesIcon.swift
//  Factum
//
//  Glasses icon — bridge and circular frames only, no sidepieces
//

import SwiftUI

/// Inline icon used in navigation bars and tab bars
struct FactumIcon: View {
    var size: CGFloat = 40
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = w * 0.04

            // Lens radius — each circular frame
            let lensR = w * 0.22
            let centerY = h * 0.5

            // Left and right lens centers — spaced so circles don't overlap
            let gap = w * 0.06
            let leftCX = w * 0.5 - lensR - gap / 2
            let rightCX = w * 0.5 + lensR + gap / 2

            // Left lens circle
            let leftLens = Path(ellipseIn: CGRect(
                x: leftCX - lensR, y: centerY - lensR,
                width: lensR * 2, height: lensR * 2
            ))
            context.stroke(leftLens, with: .color(color), lineWidth: stroke)

            // Right lens circle
            let rightLens = Path(ellipseIn: CGRect(
                x: rightCX - lensR, y: centerY - lensR,
                width: lensR * 2, height: lensR * 2
            ))
            context.stroke(rightLens, with: .color(color), lineWidth: stroke)

            // Bridge connecting the two lenses (arc curving upward)
            let bridgeLeft = leftCX + lensR
            let bridgeRight = rightCX - lensR
            var bridge = Path()
            bridge.move(to: CGPoint(x: bridgeLeft, y: centerY))
            bridge.addQuadCurve(
                to: CGPoint(x: bridgeRight, y: centerY),
                control: CGPoint(x: w * 0.5, y: centerY - w * 0.10)
            )
            context.stroke(bridge, with: .color(color),
                          style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// App icon version — solid background with centered glasses
struct FactumAppIcon: View {
    var body: some View {
        ZStack {
            // Deep charcoal background
            Color(white: 0.06)

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let stroke = w * 0.04

                // Lens radius
                let lensR = w * 0.22
                let centerY = h * 0.5

                // Left and right lens centers — spaced so circles don't overlap
                let gap = w * 0.06
                let leftCX = w * 0.5 - lensR - gap / 2
                let rightCX = w * 0.5 + lensR + gap / 2

                // Left lens circle
                let leftLens = Path(ellipseIn: CGRect(
                    x: leftCX - lensR, y: centerY - lensR,
                    width: lensR * 2, height: lensR * 2
                ))
                context.stroke(leftLens, with: .color(.white), lineWidth: stroke)

                // Right lens circle
                let rightLens = Path(ellipseIn: CGRect(
                    x: rightCX - lensR, y: centerY - lensR,
                    width: lensR * 2, height: lensR * 2
                ))
                context.stroke(rightLens, with: .color(.white), lineWidth: stroke)

                // Bridge connecting the two lenses
                let bridgeLeft = leftCX + lensR
                let bridgeRight = rightCX - lensR
                var bridge = Path()
                bridge.move(to: CGPoint(x: bridgeLeft, y: centerY))
                bridge.addQuadCurve(
                    to: CGPoint(x: bridgeRight, y: centerY),
                    control: CGPoint(x: w * 0.5, y: centerY - w * 0.10)
                )
                context.stroke(bridge, with: .color(.white),
                              style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
        }
    }
}

#Preview("Glasses Icon") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            FactumIcon(size: 48, color: .white)
            FactumIcon(size: 80, color: .white)
            FactumAppIcon()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 40))
            FactumAppIcon()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
    }
}
