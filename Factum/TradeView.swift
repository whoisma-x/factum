//
//  TradeView.swift
//  Pigeon
//
//  Trade proposals — create, view, accept/decline
//

import SwiftUI

struct TradeView: View {
    let leagueID: UUID

    @State private var trades: [TradeProposalRow] = []
    @State private var myTeam: FantasyTeamRow?
    @State private var teams: [FantasyTeamRow] = []
    @State private var allSlots: [RosterSlotRow] = []
    @State private var memberProfiles: [String: UserRow] = [:]
    @State private var isLoading = true
    @State private var appeared = false
    @State private var showCreateTrade = false
    @State private var tradeTab = 0 // 0 = Inbox, 1 = Sent
    @Environment(\.dismiss) private var dismiss

    private let uid = AuthService.shared.currentUserID

    private var inboxTrades: [TradeProposalRow] {
        trades.filter { $0.receiverTeamId == myTeam?.id && $0.status == "pending" }
    }

    private var sentTrades: [TradeProposalRow] {
        trades.filter { $0.proposerTeamId == myTeam?.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    Text("Trades")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    Button {
                        Haptics.medium()
                        showCreateTrade = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
                .padding(.top, 8)
                .staggeredAppear(index: 0, appeared: appeared)

                PigeonUnderlinePicker(
                    tabs: [0, 1],
                    selection: $tradeTab,
                    label: { $0 == 0 ? "Inbox" : "Sent" },
                    badge: { $0 == 0 && !inboxTrades.isEmpty ? inboxTrades.count : nil }
                )
                .staggeredAppear(index: 1, appeared: appeared)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    let displayTrades = tradeTab == 0 ? inboxTrades : sentTrades
                    if displayTrades.isEmpty {
                        Text(tradeTab == 0 ? "No pending trade offers" : "No sent trades")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .padding(.top, 40)
                    } else {
                        ForEach(displayTrades, id: \.id) { trade in
                            tradeCard(trade)
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
        .task { await loadData() }
        .sheet(isPresented: $showCreateTrade) {
            CreateTradeSheet(
                leagueID: leagueID,
                myTeam: myTeam,
                teams: teams,
                allSlots: allSlots,
                memberProfiles: memberProfiles
            ) {
                Task { await loadData() }
            }
        }
    }

    private func tradeCard(_ trade: TradeProposalRow) -> some View {
        let proposerName = teams.first(where: { $0.id == trade.proposerTeamId })?.teamName ?? "Team"
        let receiverName = teams.first(where: { $0.id == trade.receiverTeamId })?.teamName ?? "Team"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(proposerName) → \(receiverName)")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Spacer()
                statusBadge(trade.status)
            }

            // Offered
            VStack(alignment: .leading, spacing: 4) {
                Text("OFFERS")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                ForEach(trade.offeredSlotIds, id: \.self) { slotID in
                    if let slot = allSlots.first(where: { $0.id.uuidString == slotID }) {
                        Text("\(memberProfiles[slot.playerUid]?.displayName ?? "Player") — \(slot.subjectName)")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                }
            }

            // Requested
            VStack(alignment: .leading, spacing: 4) {
                Text("REQUESTS")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                ForEach(trade.requestedSlotIds, id: \.self) { slotID in
                    if let slot = allSlots.first(where: { $0.id.uuidString == slotID }) {
                        Text("\(memberProfiles[slot.playerUid]?.displayName ?? "Player") — \(slot.subjectName)")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                }
            }

            if let message = trade.message, !message.isEmpty {
                Text("\"\(message)\"")
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .italic()
            }

            // Action buttons (only for inbox pending trades)
            if tradeTab == 0 && trade.status == "pending" {
                HStack(spacing: 12) {
                    Button {
                        Haptics.medium()
                        Task { await respondTrade(trade, accept: true) }
                    } label: {
                        Text("Accept")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.background)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                    Button {
                        Haptics.light()
                        Task { await respondTrade(trade, accept: false) }
                    } label: {
                        Text("Decline")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.destructive)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(PigeonTheme.destructive.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .pigeonGlassSurface(cornerRadius: 14)
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(PigeonTheme.smallFont)
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.15))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "accepted": return .green
        case "declined": return PigeonTheme.destructive
        default: return PigeonTheme.tertiaryText
        }
    }

    private func respondTrade(_ trade: TradeProposalRow, accept: Bool) async {
        do {
            try await SupabaseService.shared.respondToTrade(tradeID: trade.id, accept: accept)
            Haptics.success()
            await loadData()
        } catch {
            print("[TRADE] Respond failed: \(error)")
            Haptics.error()
        }
    }

    private func loadData() async {
        do {
            let fetchedTeams = try await SupabaseService.shared.fetchFantasyTeams(leagueID: leagueID)
            teams = fetchedTeams
            myTeam = fetchedTeams.first(where: { $0.ownerUid == uid })
            allSlots = try await SupabaseService.shared.fetchAllRosterSlots(leagueID: leagueID)
            if let myTeam {
                trades = try await SupabaseService.shared.fetchTrades(leagueID: leagueID, teamID: myTeam.id)
            }
            let uids = Array(Set(allSlots.map { $0.playerUid }))
            let profiles = try await SupabaseService.shared.fetchUserProfiles(uids: uids)
            for p in profiles { memberProfiles[p.uid.uuidString] = p }
        } catch {
            print("[TRADE] Load failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Create Trade Sheet

struct CreateTradeSheet: View {
    let leagueID: UUID
    let myTeam: FantasyTeamRow?
    let teams: [FantasyTeamRow]
    let allSlots: [RosterSlotRow]
    let memberProfiles: [String: UserRow]
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReceiverTeam: FantasyTeamRow?
    @State private var offeredSlotIDs: Set<String> = []
    @State private var requestedSlotIDs: Set<String> = []
    @State private var message = ""
    @State private var isSending = false

    private let uid = AuthService.shared.currentUserID

    private var otherTeams: [FantasyTeamRow] {
        teams.filter { $0.ownerUid != uid }
    }

    private var mySlots: [RosterSlotRow] {
        allSlots.filter { $0.teamId == myTeam?.id }
    }

    private var receiverSlots: [RosterSlotRow] {
        guard let receiver = selectedReceiverTeam else { return [] }
        return allSlots.filter { $0.teamId == receiver.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Select team to trade with
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRADE WITH")
                            .pigeonSectionTitle()
                        ForEach(otherTeams, id: \.id) { team in
                            Button {
                                Haptics.light()
                                selectedReceiverTeam = team
                            } label: {
                                HStack {
                                    Text(team.teamName)
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    Spacer()
                                    if selectedReceiverTeam?.id == team.id {
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

                    // My players to offer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOU OFFER")
                            .pigeonSectionTitle()
                        ForEach(mySlots, id: \.id) { slot in
                            Button {
                                Haptics.light()
                                toggleSelection(slot.id.uuidString, in: &offeredSlotIDs)
                            } label: {
                                slotToggleRow(slot, selected: offeredSlotIDs.contains(slot.id.uuidString))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Their players to request
                    if selectedReceiverTeam != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOU REQUEST")
                                .pigeonSectionTitle()
                            ForEach(receiverSlots, id: \.id) { slot in
                                Button {
                                    Haptics.light()
                                    toggleSelection(slot.id.uuidString, in: &requestedSlotIDs)
                                } label: {
                                    slotToggleRow(slot, selected: requestedSlotIDs.contains(slot.id.uuidString))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Message
                    TextField("Add a message (optional)", text: $message)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                    // Send
                    Button {
                        Haptics.medium()
                        Task { await sendTrade() }
                    } label: {
                        if isSending {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Propose Trade").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PigeonButtonStyle())
                    .disabled(offeredSlotIDs.isEmpty || requestedSlotIDs.isEmpty || selectedReceiverTeam == nil || isSending)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(PigeonTheme.background)
            .navigationTitle("New Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PigeonTheme.bodyFont)
                }
            }
        }
    }

    private func slotToggleRow(_ slot: RosterSlotRow, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? .green : PigeonTheme.tertiaryText)
            Text(memberProfiles[slot.playerUid]?.displayName ?? "Player")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.primaryText)
            Text(slot.subjectName)
                .font(PigeonTheme.smallFont)
                .foregroundStyle(PigeonTheme.secondaryText)
            Spacer()
        }
        .padding(12)
        .pigeonGlassSurface(cornerRadius: 10)
    }

    private func toggleSelection(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func sendTrade() async {
        guard let myTeam, let receiver = selectedReceiverTeam else { return }
        isSending = true
        let row = TradeProposalRow(
            id: UUID(),
            leagueId: leagueID,
            proposerTeamId: myTeam.id,
            receiverTeamId: receiver.id,
            offeredSlotIds: Array(offeredSlotIDs),
            requestedSlotIds: Array(requestedSlotIDs),
            status: "pending",
            createdAt: Date(),
            message: message.isEmpty ? nil : message
        )
        do {
            try await SupabaseService.shared.proposeTrade(row)
            Haptics.success()
            onCreated()
            dismiss()
        } catch {
            print("[TRADE] Send failed: \(error)")
            Haptics.error()
        }
        isSending = false
    }
}
