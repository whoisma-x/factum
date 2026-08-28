//
//  FriendsView.swift
//  Pigeon
//
//  Friends — search, requests, and friend list
//

import SwiftUI
import SwiftData

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var selectedTab = 0    // 0 = Friends, 1 = Requests, 2 = Search
    @State private var searchText = ""
    @State private var searchResults: [UserRow] = []
    @State private var isSearching = false
    @State private var friendProfiles: [UserRow] = []
    @State private var pendingRequests: [(request: FriendRequestRow, sender: UserRow?)] = []
    @State private var sentRequestUIDs: Set<String> = []
    @State private var isLoading = true
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedFriend: UserRow?
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private let tabTitles = ["Friends", "Requests", "Search"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Friends")
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                }
                .padding(.top, 8)
                
                // Segmented picker
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
                        } label: {
                            HStack(spacing: 4) {
                                Text(tabTitles[index])
                                    .font(PigeonTheme.subheadlineFont)
                                    .foregroundStyle(selectedTab == index ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                if index == 1 && !pendingRequests.isEmpty {
                                    Text("\(pendingRequests.count)")
                                        .font(PigeonTheme.smallFont)
                                        .foregroundStyle(PigeonTheme.accentText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PigeonTheme.accent)
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedTab == index ? PigeonTheme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(4)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Content
                switch selectedTab {
                case 0: friendsListSection
                case 1: requestsSection
                case 2: searchSection
                default: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PigeonTheme.background)
        .task { await loadFriendsData() }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileView(
                friend: friend,
                isFriend: currentUser?.friendUIDs.contains(friend.uid.uuidString) ?? false,
                myFriendUIDs: currentUser?.friendUIDs ?? []
            )
        }
    }
    
    // MARK: - Friends List
    
    /// Friends sorted: studying first, then online, then offline.
    private var sortedFriends: [UserRow] {
        friendProfiles.sorted { a, b in
            let aOnline = isOnline(a)
            let bOnline = isOnline(b)
            let aStudying = aOnline && a.isStudying == true
            let bStudying = bOnline && b.isStudying == true
            if aStudying != bStudying { return aStudying }
            if aOnline != bOnline { return aOnline }
            return a.displayName < b.displayName
        }
    }
    
    @ViewBuilder
    private var friendsListSection: some View {
        if friendProfiles.isEmpty && !isLoading {
            VStack(spacing: 16) {
                Spacer().frame(height: 40)
                Image("Pigeon2Icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Text("No friends yet")
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                Text("Search for friends by @username")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Button {
                    selectedTab = 2
                } label: {
                    Text("Search")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.accentText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(PigeonTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        } else if isLoading {
            ProgressView()
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(sortedFriends, id: \.uid) { friend in
                    Button {
                        selectedFriend = friend
                    } label: {
                        friendRow(friend)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    /// Whether a user was seen within the last 5 minutes.
    private func isOnline(_ user: UserRow) -> Bool {
        guard let lastSeen = user.lastSeenAt else { return false }
        return Date().timeIntervalSince(lastSeen) < 300
    }
    
    private func friendRow(_ friend: UserRow) -> some View {
        HStack(spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                avatarView(name: friend.displayName, size: 44, avatarURL: friend.avatarUrl)
                
                if isOnline(friend) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(PigeonTheme.cardBackground, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                if let username = friend.username {
                    Text("@\(username)")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                // Study activity status
                if isOnline(friend), friend.isStudying == true {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Studying\(friend.currentSubject.map { " \($0)" } ?? "")")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(Color.green)
                    }
                } else if isOnline(friend) {
                    Text("Online")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(Color.green.opacity(0.7))
                }
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("\(friend.totalStudyMinutes / 60)h")
                    .font(PigeonTheme.font(16, weight: .bold))
                    .foregroundStyle(PigeonTheme.primaryText)
                Text("studied")
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                removeFriend(friend)
            } label: {
                Label("Remove Friend", systemImage: "person.badge.minus")
            }
        }
    }
    
    // MARK: - Requests
    
    @ViewBuilder
    private var requestsSection: some View {
        if pendingRequests.isEmpty {
            VStack(spacing: 16) {
                Spacer().frame(height: 40)
                Image(systemName: "bell.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(PigeonTheme.tertiaryText)
                Text("No pending requests")
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(pendingRequests, id: \.request.id) { item in
                    requestRow(item.request, sender: item.sender)
                }
            }
        }
    }
    
    private func requestRow(_ request: FriendRequestRow, sender: UserRow?) -> some View {
        HStack(spacing: 12) {
            avatarView(name: sender?.displayName ?? "User", size: 44, avatarURL: sender?.avatarUrl)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sender?.displayName ?? "User")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                if let username = sender?.username {
                    Text("@\(username)")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    Task { await acceptRequest(request) }
                } label: {
                    Text("Accept")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.accentText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(PigeonTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Button {
                    Haptics.light()
                    Task { await declineRequest(request) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .padding(8)
                        .background(PigeonTheme.elevated)
                        .clipShape(Circle())
                }
            }
        }
        .padding(14)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Search
    
    private var searchSection: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PigeonTheme.tertiaryText)
                TextField("Search by @username or name", text: $searchText)
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, _ in
                        searchTask?.cancel()
                        searchTask = Task { await performSearch() }
                    }
                if isSearching {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(14)
            .background(PigeonTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                Text("No users found")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .padding(.top, 20)
            }
            
            LazyVStack(spacing: 10) {
                ForEach(searchResults, id: \.uid) { user in
                    Button {
                        selectedFriend = user
                    } label: {
                        searchResultRow(user)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func searchResultRow(_ user: UserRow) -> some View {
        let uid = user.uid.uuidString
        let isFriend = currentUser?.friendUIDs.contains(uid) ?? false
        let isPending = sentRequestUIDs.contains(uid)
        
        return HStack(spacing: 12) {
            avatarView(name: user.displayName, size: 44, avatarURL: user.avatarUrl)
            
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
            
            if isFriend {
                Text("Friends")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PigeonTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if isPending {
                Text("Pending")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PigeonTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    Haptics.medium()
                    Task { await sendRequest(to: user) }
                } label: {
                    Text("Add")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.accentText)
                        .padding(.horizontal, 16)
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
    
    // MARK: - Data Loading
    
    private func loadFriendsData() async {
        isLoading = true
        async let f: () = loadFriendProfiles()
        async let r: () = loadPendingRequests()
        async let s: () = loadSentRequests()
        _ = await (f, r, s)
        isLoading = false
    }
    
    private func loadFriendProfiles() async {
        guard let friendUIDs = currentUser?.friendUIDs, !friendUIDs.isEmpty else {
            friendProfiles = []
            return
        }
        friendProfiles = (try? await SupabaseService.shared.fetchUserProfiles(uids: friendUIDs)) ?? []
    }
    
    private func loadPendingRequests() async {
        let uid = AuthService.shared.currentUserID
        let requests = (try? await SupabaseService.shared.fetchPendingFriendRequests(forUser: uid)) ?? []
        let senderUIDs = requests.map { $0.senderUid.uuidString }
        let senders = (try? await SupabaseService.shared.fetchUserProfiles(uids: senderUIDs)) ?? []
        let senderMap = Dictionary(uniqueKeysWithValues: senders.map { ($0.uid.uuidString, $0) })
        pendingRequests = requests.map { req in
            (request: req, sender: senderMap[req.senderUid.uuidString])
        }
    }
    
    private func loadSentRequests() async {
        let uid = AuthService.shared.currentUserID
        let sent = (try? await SupabaseService.shared.fetchSentFriendRequests(forUser: uid)) ?? []
        sentRequestUIDs = Set(sent.map { $0.receiverUid.uuidString })
    }
    
    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let uid = AuthService.shared.currentUserID
        let results = (try? await SupabaseService.shared.searchUsers(query: query)) ?? []
        searchResults = results.filter { $0.uid.uuidString != uid }
        isSearching = false
    }
    
    private func sendRequest(to user: UserRow) async {
        let uid = AuthService.shared.currentUserID
        try? await SupabaseService.shared.sendFriendRequest(from: uid, to: user.uid.uuidString)
        sentRequestUIDs.insert(user.uid.uuidString)
    }
    
    private func acceptRequest(_ request: FriendRequestRow) async {
        try? await SupabaseService.shared.acceptFriendRequest(requestID: request.id)
        currentUser?.friendUIDs.append(request.senderUid.uuidString)
        pendingRequests.removeAll { $0.request.id == request.id }
        await loadFriendProfiles()
    }
    
    private func declineRequest(_ request: FriendRequestRow) async {
        try? await SupabaseService.shared.declineFriendRequest(requestID: request.id)
        pendingRequests.removeAll { $0.request.id == request.id }
    }
    
    private func removeFriend(_ friend: UserRow) {
        let uid = AuthService.shared.currentUserID
        currentUser?.friendUIDs.removeAll { $0 == friend.uid.uuidString }
        friendProfiles.removeAll { $0.uid == friend.uid }
        Haptics.warning()
        Task {
            try? await SupabaseService.shared.removeFriend(currentUID: uid, friendUID: friend.uid.uuidString)
        }
    }
}

// MARK: - Friend Profile View

struct FriendProfileView: View {
    let friend: UserRow
    let isFriend: Bool
    let myFriendUIDs: [String]
    @Environment(\.dismiss) private var dismiss

    // Loaded stats
    @State private var sessionCount: Int = 0
    @State private var totalAppLeaves: Int = 0
    @State private var avgLeavesPerHour: Double = 0
    @State private var mutualCount: Int = 0
    @State private var isLoadingStats = true
    @State private var requestSent = false

    /// Whether the friend was seen within the last 5 minutes.
    private var isOnline: Bool {
        guard let lastSeen = friend.lastSeenAt else { return false }
        return Date().timeIntervalSince(lastSeen) < 300
    }

    /// Human-readable "last seen" text.
    private var lastSeenText: String {
        guard let lastSeen = friend.lastSeenAt else { return "Never" }
        if isOnline { return "Now" }

        let seconds = Int(Date().timeIntervalSince(lastSeen))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: lastSeen)
    }

    /// Full join date string (e.g. "August 15, 2025").
    private var joinDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: friend.joinDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header area
                    VStack(spacing: 16) {
                        // Avatar with online indicator
                        ZStack(alignment: .bottomTrailing) {
                            avatarView(name: friend.displayName, size: 88, avatarURL: friend.avatarUrl)

                            if isOnline {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(PigeonTheme.background, lineWidth: 3))
                                    .offset(x: 2, y: 2)
                            }
                        }
                        .padding(.top, 24)

                        // Name + username
                        VStack(spacing: 4) {
                            Text(friend.displayName)
                                .font(PigeonTheme.titleFont)
                                .foregroundStyle(PigeonTheme.primaryText)

                            if let username = friend.username {
                                Text("@\(username)")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.accent)
                            }
                        }

                        // Bio
                        if !friend.bio.isEmpty {
                            Text(friend.bio)
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        // Mutuals pill
                        if mutualCount > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 11))
                                Text("\(mutualCount) mutual\(mutualCount == 1 ? "" : "s")")
                                    .font(PigeonTheme.captionFont)
                            }
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(Capsule())
                        }

                        // Status pill
                        if isOnline, friend.isStudying == true {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Studying\(friend.currentSubject.map { " \($0)" } ?? "")")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(Color.green)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                        } else if isOnline {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Online")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(Color.green)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        // Add Friend button (only for non-friends)
                        if !isFriend {
                            Button {
                                Haptics.medium()
                                requestSent = true
                                Task {
                                    let uid = AuthService.shared.currentUserID
                                    try? await SupabaseService.shared.sendFriendRequest(
                                        from: uid, to: friend.uid.uuidString
                                    )
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: requestSent ? "checkmark" : "person.badge.plus")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(requestSent ? "Request Sent" : "Add Friend")
                                        .font(PigeonTheme.subheadlineFont)
                                }
                                .foregroundStyle(requestSent ? PigeonTheme.secondaryText : PigeonTheme.accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(requestSent ? PigeonTheme.elevated : PigeonTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(requestSent)
                            .padding(.horizontal, 16)
                        }
                    }

                    // Primary stats row
                    HStack(spacing: 0) {
                        statItem(
                            value: formatStudyTime(friend.totalStudyMinutes),
                            label: "Total Study"
                        )

                        Rectangle()
                            .fill(PigeonTheme.separator)
                            .frame(width: 1, height: 32)

                        statItem(
                            value: "\(friend.streakDays)",
                            label: "Day Streak"
                        )

                        Rectangle()
                            .fill(PigeonTheme.separator)
                            .frame(width: 1, height: 32)

                        statItem(
                            value: lastSeenText,
                            label: "Last Online"
                        )
                    }
                    .padding(.vertical, 16)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.top, 24)

                    // Session stats row
                    if !isLoadingStats {
                        HStack(spacing: 0) {
                            statItem(
                                value: "\(sessionCount)",
                                label: "Sessions"
                            )

                            Rectangle()
                                .fill(PigeonTheme.separator)
                                .frame(width: 1, height: 32)

                            statItem(
                                value: "\(totalAppLeaves)",
                                label: "App Leaves"
                            )

                            Rectangle()
                                .fill(PigeonTheme.separator)
                                .frame(width: 1, height: 32)

                            statItem(
                                value: String(format: "%.1f", avgLeavesPerHour),
                                label: "Leaves/hr"
                            )
                        }
                        .padding(.vertical, 16)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    } else {
                        ProgressView()
                            .padding(.top, 16)
                    }

                    // Joined date
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text("Joined \(joinDateText)")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PigeonTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await loadStats() }
        }
        .presentationBackground(PigeonTheme.background)
        .presentationDetents([.large])
    }

    private func loadStats() async {
        // Compute mutuals from friend's friendUids vs my friendUIDs
        let friendsFriends = Set(friend.friendUids)
        let myFriends = Set(myFriendUIDs)
        mutualCount = friendsFriends.intersection(myFriends).count

        // Fetch their timelapses for session stats
        let uid = friend.uid.uuidString
        let timelapses = (try? await SupabaseService.shared.fetchTimelapses(forUser: uid)) ?? []

        sessionCount = timelapses.count
        totalAppLeaves = timelapses.reduce(0) { $0 + ($1.appLeaveCount ?? 0) }

        let totalSeconds = timelapses.reduce(0) { $0 + $1.durationSeconds }
        let totalHours = Double(totalSeconds) / 3600.0
        avgLeavesPerHour = totalHours > 0 ? Double(totalAppLeaves) / totalHours : 0

        isLoadingStats = false
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(PigeonTheme.font(16, weight: .bold))
                .foregroundStyle(PigeonTheme.primaryText)
            Text(label)
                .font(PigeonTheme.smallFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatStudyTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

#Preview {
    FriendsView()
}
