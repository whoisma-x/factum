//
//  GroupsView.swift
//  Pigeon
//
//  Groups — create, leaderboard, and group feed
//

import SwiftUI
import SwiftData

struct GroupsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var groups: [StudyGroupRow] = []
    @State private var groupInvites: [(invite: GroupInviteRow, groupName: String)] = []
    @State private var showCreateGroup = false
    @State private var isLoading = true
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Groups")
                            .font(PigeonTheme.titleFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Spacer()
                        Button {
                            Haptics.medium()
                            showCreateGroup = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                    
                    // Pending invites
                    if !groupInvites.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INVITES")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                                .tracking(1)
                            
                            ForEach(groupInvites, id: \.invite.id) { item in
                                inviteRow(item.invite, groupName: item.groupName)
                            }
                        }
                    }
                    
                    // Groups list
                    if groups.isEmpty && !isLoading {
                        emptyState
                    } else if isLoading {
                        ProgressView().padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(groups, id: \.id) { group in
                                NavigationLink {
                                    GroupDetailView(group: group)
                                } label: {
                                    groupCard(group)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PigeonTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView {
                    Task { await loadGroups() }
                }
            }
            .task { await loadGroups() }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image("Pigeon3Icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(PigeonTheme.tertiaryText)
            Text("No groups yet")
                .font(PigeonTheme.headlineFont)
                .foregroundStyle(PigeonTheme.primaryText)
            Text("Create a study group to compete\nwith friends on leaderboards")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                showCreateGroup = true
            } label: {
                Text("Create Group")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.accentText)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(PigeonTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func groupCard(_ group: StudyGroupRow) -> some View {
        HStack(spacing: 14) {
            Image(systemName: group.iconName)
                .font(.system(size: 24))
                .foregroundStyle(PigeonTheme.accent)
                .frame(width: 48, height: 48)
                .background(PigeonTheme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Text("\(group.memberUids.count) member\(group.memberUids.count == 1 ? "" : "s")")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private func inviteRow(_ invite: GroupInviteRow, groupName: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(PigeonTheme.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(groupName)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Text("Group invite")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
            
            Spacer()
            
            Button {
                Haptics.success()
                Task { await acceptInvite(invite) }
            } label: {
                Text("Join")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.accentText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(PigeonTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Data
    
    private func loadGroups() async {
        isLoading = true
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { isLoading = false; return }
        
        async let g: () = loadGroupList(uid: uid)
        async let i: () = loadGroupInvites(uid: uid)
        _ = await (g, i)
        isLoading = false
    }
    
    private func loadGroupList(uid: String) async {
        groups = (try? await SupabaseService.shared.fetchGroups(forUser: uid)) ?? []
    }
    
    private func loadGroupInvites(uid: String) async {
        let invites = (try? await SupabaseService.shared.fetchGroupInvites(forUser: uid)) ?? []
        var results: [(invite: GroupInviteRow, groupName: String)] = []
        for invite in invites {
            // Fetch group name
            let groupRows: [StudyGroupRow] = (try? await SupabaseService.shared.fetchGroups(forUser: invite.inviterUid)) ?? []
            let name = groupRows.first(where: { $0.id == invite.groupId })?.name ?? "Study Group"
            results.append((invite: invite, groupName: name))
        }
        groupInvites = results
    }
    
    private func acceptInvite(_ invite: GroupInviteRow) async {
        let uid = AuthService.shared.currentUserID
        try? await SupabaseService.shared.acceptGroupInvite(
            inviteID: invite.id, groupID: invite.groupId, userUID: uid
        )
        groupInvites.removeAll { $0.invite.id == invite.id }
        await loadGroupList(uid: uid)
    }
}

// MARK: - Create Group

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon = "book.fill"
    @State private var isCreating = false
    let onCreated: () async -> Void
    
    private let iconOptions = [
        "book.fill", "pencil", "brain.head.profile.fill", "graduationcap.fill",
        "lightbulb.fill", "star.fill", "flame.fill", "bolt.fill",
        "trophy.fill", "target", "flag.fill", "heart.fill"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon picker
                    VStack(spacing: 12) {
                        Image(systemName: selectedIcon)
                            .font(.system(size: 44))
                            .foregroundStyle(PigeonTheme.accent)
                            .frame(width: 80, height: 80)
                            .background(PigeonTheme.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    Haptics.selection()
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(selectedIcon == icon ? PigeonTheme.accentText : PigeonTheme.secondaryText)
                                        .frame(width: 40, height: 40)
                                        .background(selectedIcon == icon ? PigeonTheme.accent : PigeonTheme.elevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    
                    // Form
                    VStack(spacing: 12) {
                        TextField("Group Name", text: $name)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        TextField("Description (optional)", text: $description)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        Haptics.medium()
                        isCreating = true
                        Task {
                            let uid = AuthService.shared.currentUserID
                            let group = StudyGroup(
                                name: name.trimmingCharacters(in: .whitespaces),
                                groupDescription: description.trimmingCharacters(in: .whitespaces),
                                creatorID: uid,
                                iconName: selectedIcon
                            )
                            try? await SupabaseService.shared.createStudyGroup(group)
                            await onCreated()
                            isCreating = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating { ProgressView().tint(PigeonTheme.accentText) }
                            Text("Create Group")
                                .font(PigeonTheme.subheadlineFont)
                        }
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(!name.trimmingCharacters(in: .whitespaces).isEmpty ? PigeonTheme.accent : PigeonTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
                .padding(24)
            }
            .background(PigeonTheme.background)
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
        }
        .presentationBackground(PigeonTheme.background)
    }
}

// MARK: - Group Detail

struct GroupDetailView: View {
    let group: StudyGroupRow
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @State private var leaderboard: [UserRow] = []
    @State private var selectedTab = 0   // 0 = Leaderboard, 1 = Feed
    @State private var showInvite = false
    @State private var isLoading = true
    @State private var leaderboardPeriod: LeaderboardPeriod = .allTime
    
    enum LeaderboardPeriod: String, CaseIterable {
        case daily = "Today"
        case weekly = "Week"
        case monthly = "Month"
        case yearly = "Year"
        case allTime = "All Time"
        
        /// Returns the start date for this period, or nil for all time.
        var startDate: Date? {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .daily:
                return calendar.startOfDay(for: now)
            case .weekly:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .monthly:
                return calendar.date(byAdding: .month, value: -1, to: now)
            case .yearly:
                return calendar.date(byAdding: .year, value: -1, to: now)
            case .allTime:
                return nil
            }
        }
    }
    
    private var groupFeed: [StudyTimelapse] {
        let memberSet = Set(group.memberUids)
        return allTimelapses.filter { memberSet.contains($0.authorID) }
    }
    
    /// Computes study minutes per member filtered by the selected time period.
    private var filteredLeaderboard: [(member: UserRow, minutes: Int)] {
        let memberSet = Set(group.memberUids)
        let startDate = leaderboardPeriod.startDate
        
        // Filter timelapses to this group's members and the selected period
        let relevantTimelapses = allTimelapses.filter { tl in
            guard memberSet.contains(tl.authorID) else { return false }
            if let startDate { return tl.createdAt >= startDate }
            return true
        }
        
        // Sum study minutes by author
        var minutesByUID: [String: Int] = [:]
        for tl in relevantTimelapses {
            minutesByUID[tl.authorID, default: 0] += tl.durationSeconds / 60
        }
        
        // Pair each leaderboard member with their filtered minutes, sorted descending
        return leaderboard.map { member in
            let minutes = minutesByUID[member.uid.uuidString] ?? 0
            return (member: member, minutes: minutes)
        }
        .sorted { $0.minutes > $1.minutes }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: group.iconName)
                        .font(.system(size: 36))
                        .foregroundStyle(PigeonTheme.accent)
                    Text(group.name)
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    if !group.description.isEmpty {
                        Text(group.description)
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                    Text("\(group.memberUids.count) member\(group.memberUids.count == 1 ? "" : "s")")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .padding(.top, 8)
                
                // Tab selector
                HStack(spacing: 0) {
                    ForEach(["Leaderboard", "Feed"], id: \.self) { tab in
                        let idx = tab == "Leaderboard" ? 0 : 1
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = idx }
                        } label: {
                            Text(tab)
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(selectedTab == idx ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedTab == idx ? PigeonTheme.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(4)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if selectedTab == 0 {
                    leaderboardSection
                } else {
                    feedSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .background(PigeonTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showInvite = true
                    } label: {
                        Label("Invite Member", systemImage: "person.badge.plus")
                    }
                    
                    if group.creatorUid == AuthService.shared.currentUserID {
                        Button(role: .destructive) {
                            Task {
                                try? await SupabaseService.shared.deleteGroup(id: group.id)
                                dismiss()
                            }
                        } label: {
                            Label("Delete Group", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            Task {
                                let uid = AuthService.shared.currentUserID
                                try? await SupabaseService.shared.leaveGroup(groupID: group.id, userUID: uid)
                                dismiss()
                            }
                        } label: {
                            Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteMemberView(groupID: group.id)
        }
        .task { await loadLeaderboard() }
    }
    
    // MARK: - Leaderboard
    
    @ViewBuilder
    private var leaderboardSection: some View {
        // Period picker
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            leaderboardPeriod = period
                        }
                    } label: {
                        Text(period.rawValue)
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(leaderboardPeriod == period ? PigeonTheme.accentText : PigeonTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(leaderboardPeriod == period ? PigeonTheme.accent : PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        
        if isLoading {
            ProgressView().padding(.top, 20)
        } else if leaderboard.isEmpty {
            Text("No members found")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
                .padding(.top, 20)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(Array(filteredLeaderboard.enumerated()), id: \.element.member.uid) { index, entry in
                    leaderboardRow(rank: index + 1, member: entry.member, minutes: entry.minutes)
                }
            }
        }
    }
    
    private func leaderboardRow(rank: Int, member: UserRow, minutes: Int) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(PigeonTheme.font(20, weight: .bold))
                .foregroundStyle(medalColor(for: rank))
                .frame(width: 32)
            
            avatarView(name: member.displayName, size: 40, avatarURL: member.avatarUrl)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                if let username = member.username {
                    Text("@\(username)")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }
            
            Spacer()
            
            let hours = minutes / 60
            let mins = minutes % 60
            Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                .font(PigeonTheme.font(15, weight: .bold))
                .foregroundStyle(PigeonTheme.primaryText)
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(white: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return PigeonTheme.tertiaryText
        }
    }
    
    // MARK: - Feed
    
    @ViewBuilder
    private var feedSection: some View {
        if groupFeed.isEmpty {
            VStack(spacing: 12) {
                Spacer().frame(height: 20)
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 32))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Text("No study sessions yet")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(groupFeed) { timelapse in
                    groupFeedRow(timelapse)
                }
            }
        }
    }
    
    private func groupFeedRow(_ timelapse: StudyTimelapse) -> some View {
        HStack(spacing: 12) {
            avatarView(name: timelapse.authorName, size: 36, avatarURL: timelapse.authorAvatarURL)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(timelapse.authorName)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                HStack(spacing: 6) {
                    Text(timelapse.subject)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.accent)
                    Text("·")
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    Text(timelapse.formattedDuration)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
            
            Spacer()
            
            Text(timelapse.createdAt.timeAgoDisplay())
                .font(PigeonTheme.smallFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private func loadLeaderboard() async {
        isLoading = true
        leaderboard = (try? await SupabaseService.shared.fetchGroupLeaderboard(memberUIDs: group.memberUids)) ?? []
        isLoading = false
    }
}

// MARK: - Invite Member

struct InviteMemberView: View {
    let groupID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [UserRow] = []
    @State private var isSearching = false
    @State private var sentInvites: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    TextField("Search by @username", text: $searchText)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, _ in
                            searchTask?.cancel()
                            searchTask = Task { await performSearch() }
                        }
                    if isSearching { ProgressView().scaleEffect(0.8) }
                }
                .padding(14)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(searchResults, id: \.uid) { user in
                            HStack(spacing: 12) {
                                avatarView(name: user.displayName, size: 40, avatarURL: user.avatarUrl)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(PigeonTheme.subheadlineFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    if let username = user.username {
                                        Text("@\(username)")
                                            .font(PigeonTheme.captionFont)
                                            .foregroundStyle(PigeonTheme.tertiaryText)
                                    }
                                }
                                
                                Spacer()
                                
                                if sentInvites.contains(user.uid.uuidString) {
                                    Text("Invited")
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                } else {
                                    Button {
                                        Haptics.medium()
                                        Task { await sendInvite(to: user) }
                                    } label: {
                                        Text("Invite")
                                            .font(PigeonTheme.captionFont)
                                            .foregroundStyle(PigeonTheme.accentText)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(PigeonTheme.accent)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(PigeonTheme.background)
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
        }
        .presentationBackground(PigeonTheme.background)
    }
    
    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { searchResults = []; return }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let uid = AuthService.shared.currentUserID
        let results = (try? await SupabaseService.shared.searchUsers(query: query)) ?? []
        searchResults = results.filter { $0.uid.uuidString != uid }
        isSearching = false
    }
    
    private func sendInvite(to user: UserRow) async {
        let uid = AuthService.shared.currentUserID
        try? await SupabaseService.shared.inviteToGroup(
            groupID: groupID, inviterUID: uid, inviteeUID: user.uid.uuidString
        )
        sentInvites.insert(user.uid.uuidString)
    }
}

#Preview {
    GroupsView()
}
