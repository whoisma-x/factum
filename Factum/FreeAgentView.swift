//
//  FreeAgentView.swift
//  Pigeon
//
//  Free agent pickups — browse and add/drop players
//

import SwiftUI
import SwiftData

struct FreeAgentView: View {
    let leagueID: UUID
    @Query private var localTimelapses: [StudyTimelapse]

    @State private var league: FantasyLeagueRow?
    @State private var myTeam: FantasyTeamRow?
    @State private var mySlots: [RosterSlotRow] = []
    @State private var allSlots: [RosterSlotRow] = []
    @State private var freeAgents: [(uid: String, displayName: String, subject: String)] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @State private var showDropPicker = false
    @State private var pendingPickup: (uid: String, subject: String)?
    @Environment(\.dismiss) private var dismiss

    private let uid = AuthService.shared.currentUserID

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Free Agents")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if freeAgents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("No free agents available")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .padding(.top, 40)
                } else {
                    Text("\(freeAgents.count) available")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .staggeredAppear(index: 1, appeared: appeared)

                    ForEach(Array(freeAgents.enumerated()), id: \.offset) { index, agent in
                        let (weekStart, weekEnd) = LeagueScoringEngine.weekBounds(for: Date())
                        let config = ScoringConfig.from(json: league?.scoringConfigJson)
                        let score = LeagueScoringEngine.calculateScore(
                            playerUID: agent.uid,
                            subject: agent.subject,
                            timelapses: localTimelapses,
                            weekStart: weekStart,
                            weekEnd: weekEnd,
                            config: config
                        )

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(PigeonTheme.accent)
                                    .frame(width: 40, height: 40)
                                Text(String(agent.displayName.prefix(1)))
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayName)
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                    .lineLimit(1)
                                Text(agent.subject)
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.secondaryText)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.1f", score.finalScore))
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Text("this week")
                                    .font(.gloucester(size: 10))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }

                            Button {
                                Haptics.medium()
                                pendingPickup = (agent.uid, agent.subject)
                                showDropPicker = true
                            } label: {
                                Text("Add")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.background)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(PigeonTheme.primaryText)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(14)
                        .pigeonGlassSurface(cornerRadius: 14)
                        .staggeredAppear(index: index + 2, appeared: appeared)
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
        .sheet(isPresented: $showDropPicker) {
            dropPickerSheet
        }
    }

    // MARK: - Drop Picker

    private var dropPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Choose a player to drop")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(.top, 16)

                    ForEach(mySlots, id: \.id) { slot in
                        Button {
                            Haptics.medium()
                            Task {
                                await pickupPlayer(dropSlot: slot)
                                showDropPicker = false
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Text(slot.subjectName)
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.secondaryText)
                                Spacer()
                                Text("Drop")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.destructive)
                            }
                            .padding(14)
                            .pigeonGlassSurface(cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(PigeonTheme.background)
            .navigationTitle("Drop Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDropPicker = false }
                        .font(PigeonTheme.bodyFont)
                }
            }
        }
    }

    private func pickupPlayer(dropSlot: RosterSlotRow) async {
        guard let myTeam, let pickup = pendingPickup else { return }
        do {
            try await SupabaseService.shared.pickupFreeAgent(
                leagueID: leagueID,
                teamID: myTeam.id,
                dropSlotID: dropSlot.id,
                playerUID: pickup.uid,
                subjectName: pickup.subject
            )
            Haptics.success()
            await loadData()
        } catch {
            print("[FA] Pickup failed: \(error)")
            Haptics.error()
        }
    }

    private func loadData() async {
        do {
            league = try await SupabaseService.shared.fetchFantasyLeague(id: leagueID)
            let teams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            myTeam = teams.first(where: { $0.ownerUid == uid })
            allSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)

            if let myTeam {
                mySlots = allSlots.filter { $0.teamId == myTeam.id }
            }

            // Build free agent pool
            guard let league else { return }
            let memberSubjects = try await SupabaseService.shared.fetchMemberSubjects(memberUIDs: league.memberUids)
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: league.memberUids)
            for p in profiles { memberProfiles[p.uid.uuidString] = p }
            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.uid.uuidString, $0.displayName) })

            let drafted = Set(allSlots.map { "\($0.playerUid)|\($0.subjectName)" })
            freeAgents = memberSubjects.flatMap { item in
                item.subjects.compactMap { subject in
                    let key = "\(item.uid)|\(subject)"
                    guard !drafted.contains(key) else { return nil }
                    return (uid: item.uid, displayName: profileMap[item.uid] ?? "Unknown", subject: subject)
                }
            }
        } catch {
            print("[FA] Load failed: \(error)")
        }
        isLoading = false
    }
}
