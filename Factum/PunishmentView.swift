//
//  PunishmentView.swift
//  Pigeon
//
//  Weekly punishments — propose, vote, and video announcements
//

import SwiftUI
import AVKit

struct PunishmentView: View {
    let leagueID: UUID

    @State private var league: FantasyLeagueRow?
    @State private var punishments: [PunishmentRow] = []
    @State private var teams: [FantasyTeamRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @State private var showPropose = false
    @Environment(\.dismiss) private var dismiss

    private let uid = AuthService.shared.currentUserID
    private var isCommissioner: Bool { league?.commissionerUid == uid }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Punishments")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    if isCommissioner {
                        Button {
                            Haptics.medium()
                            showPropose = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    }
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if punishments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("No punishments yet")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        if isCommissioner {
                            Text("As commissioner, you can propose punishments for the lowest scorers.")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(Array(punishments.enumerated()), id: \.element.id) { index, punishment in
                        punishmentCard(punishment)
                            .staggeredAppear(index: index + 1, appeared: appeared)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .pigeonWallpaper()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { withAnimation { appeared = true } }
        .task { await loadData() }
        .sheet(isPresented: $showPropose) {
            ProposePunishmentSheet(leagueID: leagueID, teams: teams, memberProfiles: memberProfiles) {
                Task { await loadData() }
            }
        }
    }

    private func punishmentCard(_ punishment: PunishmentRow) -> some View {
        let targetName = memberProfiles[punishment.targetUid]?.displayName ?? "Unknown"
        let memberCount = league?.memberUids.count ?? 1
        let approvalNeeded = max(1, memberCount / 2)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Week \(punishment.weekNumber)")
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Spacer()
                punishmentStatusBadge(punishment.status)
            }

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(targetName)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }

            Text(punishment.reason == "lowest_score" ? "Lowest team score" : "Least study time")
                .font(PigeonTheme.smallFont)
                .foregroundStyle(PigeonTheme.secondaryText)

            if !punishment.punishmentDescription.isEmpty {
                Text(punishment.punishmentDescription)
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }

            // Video player
            if let videoURLString = punishment.videoUrl, let videoURL = URL(string: videoURLString) {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Voting
            if punishment.status == "proposed" {
                HStack {
                    Text("\(punishment.approvalVotes.count)/\(approvalNeeded) votes")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    Spacer()
                    if !punishment.approvalVotes.contains(uid) {
                        Button {
                            Haptics.medium()
                            Task { await vote(punishment) }
                        } label: {
                            Text("Approve")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.background)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(PigeonTheme.primaryText)
                                .clipShape(Capsule())
                        }
                    } else {
                        Text("Voted")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
            }
        }
        .padding(16)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    private func punishmentStatusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "proposed": return .orange
            case "approved": return .green
            case "completed": return .blue
            default: return PigeonTheme.tertiaryText
            }
        }()
        return Text(status.capitalized)
            .font(PigeonTheme.smallFont)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func vote(_ punishment: PunishmentRow) async {
        do {
            try await SupabaseService.shared.votePunishment(punishmentID: punishment.id, voterUID: uid)
            Haptics.success()
            await loadData()
        } catch {
            print("[PUNISH] Vote failed: \(error)")
        }
    }

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            punishments = try await SupabaseService.shared.fetchPunishments(leagueID: leagueID)
            teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            if let league {
                let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
                for p in profiles { memberProfiles[p.uid.uuidString] = p }
            }
        } catch {
            print("[PUNISH] Load failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Propose Punishment Sheet

struct ProposePunishmentSheet: View {
    let leagueID: UUID
    let teams: [FantasyTeamRow]
    let memberProfiles: [String: UserRow]
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTargetUID: String?
    @State private var reason = "lowest_score"
    @State private var description = ""
    @State private var weekNumber = 1
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Target selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHO GETS PUNISHED")
                            .pigeonSectionTitle()
                        ForEach(teams, id: \.id) { team in
                            Button {
                                Haptics.light()
                                selectedTargetUID = team.ownerUid
                            } label: {
                                HStack {
                                    Text(team.teamName)
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    if let name = memberProfiles[team.ownerUid]?.displayName {
                                        Text("(\(name))")
                                            .font(PigeonTheme.smallFont)
                                            .foregroundStyle(PigeonTheme.tertiaryText)
                                    }
                                    Spacer()
                                    if selectedTargetUID == team.ownerUid {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(12)
                                .pigeonGlassSurface(cornerRadius: 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Reason
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REASON")
                            .pigeonSectionTitle()
                        Picker("Reason", selection: $reason) {
                            Text("Lowest Team Score").tag("lowest_score")
                            Text("Least Studied").tag("least_studied")
                        }
                        .pickerStyle(.segmented)
                    }

                    // Week
                    HStack {
                        Text("Week")
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Spacer()
                        Stepper("\(weekNumber)", value: $weekNumber, in: 1...52)
                            .font(PigeonTheme.bodyFont)
                            .frame(width: 140)
                    }
                    .padding(14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PUNISHMENT DESCRIPTION")
                            .pigeonSectionTitle()
                        TextField("Describe the punishment...", text: $description, axis: .vertical)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .lineLimit(3...6)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    Button {
                        Haptics.medium()
                        Task { await proposePunishment() }
                    } label: {
                        if isSending {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Propose Punishment").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PigeonButtonStyle())
                    .disabled(selectedTargetUID == nil || isSending)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(PigeonTheme.background)
            .navigationTitle("Propose Punishment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PigeonTheme.bodyFont)
                }
            }
        }
    }

    private func proposePunishment() async {
        guard let targetUID = selectedTargetUID else { return }
        isSending = true
        let row = PunishmentRow(
            id: UUID(),
            leagueId: leagueID,
            weekNumber: weekNumber,
            targetUid: targetUID,
            reason: reason,
            punishmentDescription: description,
            approvalVotes: [],
            status: "proposed",
            createdAt: Date()
        )
        do {
            try await SupabaseService.shared.proposePunishment(row)
            Haptics.success()
            onCreated()
            dismiss()
        } catch {
            print("[PUNISH] Propose failed: \(error)")
            Haptics.error()
        }
        isSending = false
    }
}
