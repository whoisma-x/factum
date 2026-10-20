//
//  CreateLeagueView.swift
//  Pigeon
//
//  Sheet for creating a new fantasy study league
//

import SwiftUI
import SwiftData

struct CreateLeagueView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [UserProfile]
    var onCreated: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon = "trophy.fill"
    @State private var selectedFormat: LeagueFormat = .standard
    @State private var rosterSize = 8
    @State private var benchSize = 3
    @State private var seasonEndDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var playoffTeams = 4
    @State private var draftSecondsPerPick = 90
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var customEmoji = ""
    @State private var showEmojiField = false
    @State private var slotMultipliers: [Int] = FantasyLeagueRow.defaultSlotConfig(rosterSize: 8)
    @State private var showSlotConfig = false

    private let icons = [
        "trophy.fill", "flame.fill", "bolt.fill", "star.fill",
        "book.fill", "brain.head.profile.fill", "graduationcap.fill",
        "target", "flag.fill", "crown.fill", "medal.fill", "chart.bar.fill"
    ]

    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LEAGUE ICON")
                            .pigeonSectionTitle()

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(icons, id: \.self) { icon in
                                Button {
                                    Haptics.light()
                                    selectedIcon = icon
                                    showEmojiField = false
                                    customEmoji = ""
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(selectedIcon == icon && !showEmojiField ? PigeonTheme.primaryText : PigeonTheme.cardBackground)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(selectedIcon == icon && !showEmojiField ? PigeonTheme.background : PigeonTheme.secondaryText)
                                    }
                                }
                            }

                            // Custom emoji button
                            Button {
                                Haptics.light()
                                showEmojiField = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(showEmojiField ? PigeonTheme.primaryText : PigeonTheme.cardBackground)
                                        .frame(width: 48, height: 48)
                                    if !customEmoji.isEmpty {
                                        Text(customEmoji)
                                            .font(.gloucester(size: 22))
                                    } else {
                                        Text("Aa")
                                            .font(.gloucester(size: 16))
                                            .foregroundStyle(showEmojiField ? PigeonTheme.background : PigeonTheme.secondaryText)
                                    }
                                }
                            }
                        }

                        if showEmojiField {
                            HStack(spacing: 10) {
                                TextField("Type an emoji", text: $customEmoji)
                                    .font(.gloucester(size: 28))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 60, height: 44)
                                    .background(PigeonTheme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                                    .onChange(of: customEmoji) { _, newValue in
                                        // Keep only the first emoji character
                                        if let first = newValue.first, first.isEmoji {
                                            customEmoji = String(first)
                                            selectedIcon = "emoji:\(first)"
                                        } else if newValue.isEmpty {
                                            // Allow clearing
                                        } else {
                                            customEmoji = ""
                                        }
                                    }
                                Text("Pick any emoji as your league icon")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                        }
                    }

                    // Format Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LEAGUE FORMAT")
                            .pigeonSectionTitle()

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                            ForEach(LeagueFormat.allCases) { format in
                                Button {
                                    Haptics.light()
                                    applyFormat(format)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: format.icon)
                                            .font(.system(size: 18))
                                            .foregroundStyle(selectedFormat == format ? PigeonTheme.background : PigeonTheme.secondaryText)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(format.displayName)
                                                .font(PigeonTheme.captionFont)
                                                .foregroundStyle(selectedFormat == format ? PigeonTheme.background : PigeonTheme.primaryText)
                                            Text(format.subtitle)
                                                .font(.gloucester(size: 11))
                                                .foregroundStyle(selectedFormat == format ? PigeonTheme.background.opacity(0.7) : PigeonTheme.tertiaryText)
                                                .lineLimit(1)
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(selectedFormat == format ? PigeonTheme.primaryText : PigeonTheme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                                }
                            }
                        }

                        if selectedFormat != .custom {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                Text(selectedFormat.slotDescription)
                                    .font(PigeonTheme.smallFont)
                            }
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    }

                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEAGUE NAME")
                            .pigeonSectionTitle()
                        TextField("e.g. IB Study League", text: $name)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION")
                            .pigeonSectionTitle()
                        TextField("Optional", text: $description)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    // Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("LEAGUE SETTINGS")
                            .pigeonSectionTitle()

                        if selectedFormat == .custom {
                            settingsRow("Roster Size", value: $rosterSize, range: 2...12)
                                .onChange(of: rosterSize) { _, newSize in
                                    slotMultipliers = FantasyLeagueRow.defaultSlotConfig(rosterSize: newSize)
                                }
                            settingsRow("Bench Slots", value: $benchSize, range: 0...5)
                        } else {
                            readOnlyRow("Roster Size", value: rosterSize)
                            readOnlyRow("Bench Slots", value: benchSize)
                        }

                        settingsRow("Playoff Teams", value: $playoffTeams, range: 2...8)

                        // Slot Multiplier Config
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.smooth(duration: 0.25)) {
                                    showSlotConfig.toggle()
                                }
                            } label: {
                                HStack {
                                    Text("Slot Multipliers")
                                        .font(PigeonTheme.bodyFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    Spacer()
                                    Text(slotSummary)
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                    Image(systemName: showSlotConfig ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                }
                            }

                            if showSlotConfig {
                                Text("Points scored by each active slot are multiplied. Drag to reorder.")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)

                                ForEach(slotMultipliers.indices, id: \.self) { i in
                                    HStack(spacing: 12) {
                                        Text("Slot \(i + 1)")
                                            .font(PigeonTheme.captionFont)
                                            .foregroundStyle(PigeonTheme.secondaryText)
                                            .frame(width: 50, alignment: .leading)

                                        ForEach([1, 2, 3], id: \.self) { mult in
                                            Button {
                                                Haptics.light()
                                                slotMultipliers[i] = mult
                                            } label: {
                                                Text("\(mult)×")
                                                    .font(PigeonTheme.captionFont)
                                                    .foregroundStyle(slotMultipliers[i] == mult ? PigeonTheme.background : PigeonTheme.secondaryText)
                                                    .frame(width: 40, height: 32)
                                                    .background(slotMultipliers[i] == mult ? multiplierColor(mult) : PigeonTheme.cardBackground)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                        Spacer()
                                    }
                                }

                                Button {
                                    Haptics.light()
                                    slotMultipliers = FantasyLeagueRow.defaultSlotConfig(rosterSize: rosterSize)
                                } label: {
                                    Text("Reset to Default")
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                }
                            }
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                        HStack {
                            Text("Draft Timer")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Picker("", selection: $draftSecondsPerPick) {
                                Text("60s").tag(60)
                                Text("90s").tag(90)
                                Text("120s").tag(120)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                        HStack {
                            Text("Season End")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            DatePicker("", selection: $seasonEndDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    // Create Button
                    Button {
                        Haptics.medium()
                        Task { await createLeague() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create League")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PigeonButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(PigeonTheme.background)
            .navigationTitle("New League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PigeonTheme.bodyFont)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func settingsRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.primaryText)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
                .font(PigeonTheme.bodyFont)
                .frame(width: 140)
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
    }

    private func readOnlyRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.primaryText)
            Spacer()
            Text("\(value)")
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.secondaryText)
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
    }

    private func applyFormat(_ format: LeagueFormat) {
        selectedFormat = format
        if format != .custom {
            rosterSize = format.rosterSize
            benchSize = format.benchSize
            slotMultipliers = format.slotMultipliers
        }
    }

    private func createLeague() async {
        isCreating = true
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { isCreating = false; return }

        let league = FantasyLeague(
            name: name.trimmingCharacters(in: .whitespaces),
            commissionerUID: uid,
            seasonEndDate: seasonEndDate,
            maxRosterSize: rosterSize,
            benchSize: benchSize,
            playoffTeamCount: playoffTeams,
            iconName: selectedIcon,
            leagueDescription: description,
            draftSecondsPerPick: draftSecondsPerPick
        )
        // Encode slot multiplier config
        if let data = try? JSONEncoder().encode(slotMultipliers) {
            league.slotConfigJSON = String(data: data, encoding: .utf8)
        }

        do {
            try await SupabaseService.shared.createFantasyLeague(league)
            // Create commissioner's team
            let teamName = "\(currentUser?.displayName ?? "Commissioner")'s Team"
            try await SupabaseService.shared.createFantasyTeam(
                leagueID: league.id,
                ownerUID: uid,
                teamName: teamName
            )
            Haptics.success()
            onCreated()
            dismiss()
        } catch {
            print("[LEAGUE] Create failed: \(error)")
            errorMessage = "Failed to create league. Make sure the Supabase fantasy league tables have been set up."
            Haptics.error()
        }

        isCreating = false
    }

    private var slotSummary: String {
        let count3 = slotMultipliers.filter { $0 == 3 }.count
        let count2 = slotMultipliers.filter { $0 == 2 }.count
        let count1 = slotMultipliers.filter { $0 == 1 }.count
        var parts: [String] = []
        if count3 > 0 { parts.append("\(count3)×3x") }
        if count2 > 0 { parts.append("\(count2)×2x") }
        if count1 > 0 { parts.append("\(count1)×1x") }
        return parts.joined(separator: ", ")
    }

    private func multiplierColor(_ mult: Int) -> Color {
        switch mult {
        case 3: return .orange
        case 2: return .blue
        default: return PigeonTheme.secondaryText
        }
    }
}

// MARK: - Emoji Detection

private extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
