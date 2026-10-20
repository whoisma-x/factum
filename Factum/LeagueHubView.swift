//
//  LeagueHubView.swift
//  Pigeon
//
//  Main league tab — list of user's leagues + invites
//

import SwiftUI
import SwiftData

struct LeagueHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var leagues: [FantasyLeagueRow] = []
    @State private var invites: [(invite: LeagueInviteRow, leagueName: String)] = []
    @State private var teams: [UUID: FantasyTeamRow] = [:]
    @State private var showCreateLeague = false
    @State private var isLoading = true
    @State private var appeared = false
    @State private var hubTab = 0

    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack(alignment: .firstTextBaseline) {
                        Text("Leagues")
                            .font(PigeonTheme.titleFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Spacer()
                        Button {
                            Haptics.medium()
                            showCreateLeague = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                    }
                    .padding(.top, 8)
                    .staggeredAppear(index: 0, appeared: appeared)

                    PigeonUnderlinePicker(
                        tabs: [0, 1],
                        selection: $hubTab,
                        label: { $0 == 0 ? "My Leagues" : "Invites" },
                        badge: { tab in
                            tab == 1 && !invites.isEmpty ? invites.count : nil
                        }
                    )
                    .staggeredAppear(index: 1, appeared: appeared)

                    if hubTab == 0 {
                        if leagues.isEmpty && !isLoading {
                            emptyState
                        } else if isLoading {
                            ProgressView().padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(leagues.enumerated()), id: \.element.id) { index, league in
                                    NavigationLink {
                                        LeagueDashboardView(leagueID: league.id)
                                    } label: {
                                        leagueCard(league)
                                    }
                                    .buttonStyle(.plain)
                                    .staggeredAppear(index: index + 2, appeared: appeared)
                                }
                            }
                        }
                    } else {
                        if invites.isEmpty {
                            VStack(spacing: 12) {
                                Spacer().frame(height: 32)
                                Image(systemName: "envelope.badge")
                                    .font(.system(size: 36))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                                Text("no invites yet")
                                    .font(.gloucester(size: 22))
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Text("League invitations will appear here")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(invites, id: \.invite.id) { item in
                                    inviteRow(item.invite, leagueName: item.leagueName)
                                }
                            }
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
            .sheet(isPresented: $showCreateLeague) {
                CreateLeagueView {
                    Task { await loadLeagues() }
                }
            }
            .task { await loadLeagues() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 24)
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(PigeonTheme.tertiaryText)
            Text("no leagues yet")
                .font(.gloucester(size: 22))
                .foregroundStyle(PigeonTheme.primaryText)
            Text("Create a league and invite your friends to compete in fantasy study.")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                Haptics.medium()
                showCreateLeague = true
            } label: {
                Text("Create League")
            }
            .buttonStyle(PigeonButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - League Card

    private func leagueCard(_ league: FantasyLeagueRow) -> some View {
        HStack(spacing: 14) {
            // League icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(PigeonTheme.accent)
                    .frame(width: 52, height: 52)
                if league.iconName.hasPrefix("emoji:") {
                    Text(String(league.iconName.dropFirst(6)))
                        .font(.system(size: 26))
                } else {
                    Image(systemName: league.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(PigeonTheme.primaryText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(league.name)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label("\(league.memberUids.count)", systemImage: "person.2.fill")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)

                    statusBadge(league.draftStatus)

                    if let myTeam = teams[league.id] {
                        Text("\(myTeam.wins)-\(myTeam.losses)")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(PigeonTheme.smallFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .padding(14)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "pending": return ("PRE-DRAFT", PigeonTheme.tertiaryText)
            case "in_progress": return ("DRAFTING", .orange)
            case "completed": return ("ACTIVE", .green)
            default: return (status.uppercased(), PigeonTheme.tertiaryText)
            }
        }()

        return Text(label)
            .font(.gloucester(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Invite Row

    private func inviteRow(_ invite: LeagueInviteRow, leagueName: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(PigeonTheme.accent)
                    .frame(width: 42, height: 42)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(PigeonTheme.primaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(leagueName)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Text("League invite")
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }

            Spacer()

            Button {
                Haptics.medium()
                Task { await acceptInvite(invite) }
            } label: {
                Text("Join")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(PigeonTheme.primaryText)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    // MARK: - Data Loading

    private func loadLeagues() async {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { isLoading = false; return }

        do {
            async let leagueResult = SupabaseService.shared.fetchFantasyLeagues(forUser: uid)
            async let inviteResult = SupabaseService.shared.fetchFantasyLeagueInvites(forUser: uid)

            leagues = try await leagueResult
            let rawInvites = try await inviteResult

            var named: [(invite: LeagueInviteRow, leagueName: String)] = []
            for inv in rawInvites {
                if let league = try? await SupabaseService.shared.fetchFantasyLeague(id: inv.leagueId) {
                    named.append((inv, league.name))
                }
            }
            invites = named

            for league in leagues {
                let teamRows = try await SupabaseService.shared.fetchFantasyTeams(leagueID: league.id)
                if let myTeam = teamRows.first(where: { $0.ownerUid == uid }) {
                    teams[league.id] = myTeam
                }
            }
        } catch {
            print("[LEAGUE] Failed to load leagues: \(error)")
        }

        isLoading = false
    }

    private func acceptInvite(_ invite: LeagueInviteRow) async {
        let uid = AuthService.shared.currentUserID
        let name = currentUser?.displayName ?? "My Team"
        do {
            try await SupabaseService.shared.acceptFantasyLeagueInvite(
                inviteID: invite.id,
                leagueID: invite.leagueId,
                userUID: uid,
                teamName: "\(name)'s Team"
            )
            Haptics.success()
            await loadLeagues()
        } catch {
            print("[LEAGUE] Accept invite failed: \(error)")
        }
    }
}
