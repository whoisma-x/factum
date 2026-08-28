//
//  GlassesIcon.swift
//  Pigeon
//
//  Pigeon mascot — elegant line-art portrait with graduation cap & monocle
//

import SwiftUI

/// Inline pigeon mascot icon used throughout the app.
/// Uses the original pigeon line-art image as a template, tinted to the given color.
struct PigeonIcon: View {
    var size: CGFloat = 40
    var color: Color = Color(red: 0.98, green: 0.96, blue: 0.90)

    var body: some View {
        Image("PigeonLogo")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

/// App icon version — solid background with centered pigeon
struct PigeonAppIcon: View {
    var body: some View {
        ZStack {
            Color(white: 0.06)
            PigeonIcon(size: 500)
                .scaleEffect(0.55)
        }
    }
}

#Preview("Pigeon Mascot") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            PigeonIcon(size: 48)
            PigeonIcon(size: 80)
            PigeonIcon(size: 160)
            PigeonAppIcon()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 40))
            PigeonAppIcon()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
    }
}
