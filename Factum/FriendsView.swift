//
//  FriendsView.swift
//  Factum
//
//  Friends - Coming Soon placeholder
//

import SwiftUI

struct FriendsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("Friends")
                        .font(FactumTheme.titleFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                
                Spacer().frame(height: 40)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(FactumTheme.tertiaryText)
                
                Text("Coming Soon")
                    .font(FactumTheme.headlineFont)
                    .foregroundStyle(FactumTheme.accent)
                
                Text("Add friends, see what they're studying,\nand hold each other accountable.")
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FactumTheme.background)
    }
}

#Preview {
    FriendsView()
}
