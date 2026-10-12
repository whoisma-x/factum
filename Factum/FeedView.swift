//
//  FeedView.swift
//  Pigeon
//
//  Home feed showing study timelapse posts
//

import SwiftUI
import SwiftData
import AVKit

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WallpaperManager.self) private var wallpaperManager
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @Query private var users: [UserProfile]
    @State private var showingNewTimelapse = false
    @State private var publicAuthorUIDs: [String] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var appeared = false
    
    /// Number of the current user's sessions not yet backed up to Supabase.
    private var unsyncedCount: Int {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid && !$0.cloudSynced }.count
    }
    
    private var timelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        let friendUIDs = currentUser?.friendUIDs ?? []
        let allowedUIDs = Set([uid] + friendUIDs + publicAuthorUIDs)
        var feed = allTimelapses.filter { allowedUIDs.contains($0.authorID) }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            feed = feed.filter {
                $0.subject.lowercased().contains(query) ||
                $0.caption.lowercased().contains(query) ||
                $0.studyDescription.lowercased().contains(query)
            }
        }
        return feed.sorted { a, b in
            let aRarity = PunRarity(rawValue: a.descriptionRarity ?? "") ?? .common
            let bRarity = PunRarity(rawValue: b.descriptionRarity ?? "") ?? .common
            let aBoosted = a.createdAt.addingTimeInterval(aRarity.feedBoostSeconds)
            let bBoosted = b.createdAt.addingTimeInterval(bRarity.feedBoostSeconds)
            return aBoosted > bBoosted
        }
    }
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    // MARK: - Pigeon Study Greetings
    
    private static let generalGreetings = [
        "coo coo, time to study",
        "spread your wings",
        "don't be a bird brain",
        "time to ruffle some pages",
        "nest up and focus",
        "fly through those notes",
        "peck away at it",
        "feathers down, books open",
        "wings up",
        "carrier pigeon mode: on",
        "flocking to the books",
        "perched and ready",
        "hatching some knowledge",
        "this pigeon doesn't rest",
        "coo'd you study any harder",
        "let's get cooing",
        "pigeon brain activated",
        "strut your stuff",
        "delivering grades, one coo at a time",
        "no crumbs, only textbooks",
        "this nest runs on focus",
        "time to spread those study wings",
        "pecking order: you, then everyone else",
        "ruffle feathers, not deadlines",
        "stay on the perch",
        "beak deep in the books",
        "coo-lcapigeons study hard",
        "bread crumbs can wait",
        "fly above the average",
        "pluck up the courage to study",
        "pigeon post: you got this",
        "the flock is proud of you",
        "one coo at a time",
        "let's wing this",
        "bob your head and get to work",
        "homing in on those grades",
        "don't fly away from your notes",
        "even pigeons grind",
    ]
    
    private static let morningGreetings = [
        "early bird gets the A",
        "rise and grind, pigeon",
        "morning coo, time to study",
        "the early pigeon catches the grade",
        "dawn patrol, books out",
        "fresh feathers, fresh start",
        "sunrise study sesh",
        "up with the pigeons",
    ]
    
    private static let noonGreetings = [
        "midday study flight",
        "lunch break? study break",
        "peak hours, peak focus",
        "noon coo, lock in",
        "sun's high, so are your standards",
        "the afternoon grind awaits",
        "cooing through the afternoon",
        "no nap, only notes",
    ]
    
    private static let eveningGreetings = [
        "evening coo, still at it",
        "sunset study session",
        "golden hour for golden grades",
        "winding down? wind up the books",
        "the evening pigeon studies hardest",
        "cooing into the evening",
        "dusk doesn't mean done",
        "twilight grind",
    ]
    
    private static let nightGreetings = [
        "night owl pigeon mode",
        "moonlit study sesh",
        "the city sleeps, you study",
        "burning the midnight feathers",
        "late night coo crew",
        "the stars are out, so are your notes",
        "nocturnal pigeon energy",
        "quiet hours, loud progress",
    ]
    
    @AppStorage("lastGreetingIndex") private static var lastGreetingIndex: Int = -1
    @AppStorage("lastGreetingPool") private static var lastGreetingPool: String = ""
    
    /// Picked once per app launch, stays stable across re-renders.
    @State private var frozenGreeting: String? = nil
    
    private static var timeOfDayGreetings: [String] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return morningGreetings
        case 12..<17: return noonGreetings
        case 17..<21: return eveningGreetings
        default: return nightGreetings
        }
    }
    
    private var greeting: String {
        if let frozenGreeting { return frozenGreeting }
        // Mix general greetings with time-of-day specific ones
        let pool = Self.generalGreetings + Self.timeOfDayGreetings
        var index: Int
        repeat {
            index = Int.random(in: 0..<pool.count)
        } while index == Self.lastGreetingIndex && pool.count > 1
        Self.lastGreetingIndex = index
        return pool[index]
    }
    
    private var firstName: String {
        let name = currentUser?.displayName ?? "Student"
        return name.components(separatedBy: " ").first ?? name
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Top bar: centered logo + search toggle
                    ZStack {
                        // Centered logo
                        HStack(spacing: 8) {
                            PigeonIcon(size: 28, color: PigeonTheme.primaryText)
                            Text("pigeon.")
                                .font(.gloucester(size: 28))
                                .foregroundStyle(PigeonTheme.primaryText)
                                .tracking(2)
                        }
                        
                        // Search button (right side)
                        HStack {
                            Spacer()
                            Button {
                                Haptics.light()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSearching.toggle()
                                    if !isSearching { searchText = "" }
                                }
                            } label: {
                                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(PigeonTheme.primaryText)
                                    .frame(width: 32, height: 32)
                                    .pigeonGlassSurface(cornerRadius: 16)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .staggeredAppear(index: 0, appeared: appeared)
                    
                    // Search bar
                    if isSearching {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(PigeonTheme.tertiaryText)
                            TextField("Search by subject, caption...", text: $searchText)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .pigeonGlassSurface(cornerRadius: 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Greeting + streak section (like Strava's streak card)
                    VStack(spacing: 14) {
                        Text("\(greeting), \(firstName).")
                            .font(.gloucester(size: 18))
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                        
                        // Quick stats row
                        if let user = currentUser {
                            quickStatsBar(user: user)
                        }
                    }
                    .staggeredAppear(index: 1, appeared: appeared)
                    
                    // Unsynced sessions warning
                    if unsyncedCount > 0, appeared {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.slash")
                                .font(.system(size: 14, weight: .medium))
                            Text("\(unsyncedCount) session\(unsyncedCount == 1 ? "" : "s") not yet backed up")
                                .font(PigeonTheme.smallFont)
                            Spacer()
                            ProgressView()
                                .tint(PigeonTheme.primaryText.opacity(0.7))
                                .scaleEffect(0.7)
                        }
                        .foregroundStyle(PigeonTheme.primaryText.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(PigeonTheme.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // Feed
                    LazyVStack(spacing: 20) {
                        if timelapses.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 36))
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                                Text("no matches found")
                                    .font(.gloucester(size: 18))
                                    .foregroundStyle(PigeonTheme.secondaryText)
                                Text("Try a different search term")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        } else if timelapses.isEmpty {
                            emptyState
                        } else {
                            ForEach(timelapses) { timelapse in
                                TimelapseCardView(timelapse: timelapse)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .pigeonWallpaper()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if frozenGreeting == nil { frozenGreeting = greeting }
                withAnimation { appeared = true }
            }
            .task { await loadPublicFeed() }
            .fullScreenCover(isPresented: $showingNewTimelapse) {
                TimelapseCameraView()
            }
        }
    }
    
    // MARK: - Quick Stats Bar (Strava streak-style)
    
    private var myTimelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid }
    }
    
    private var streakDays: Int {
        guard !myTimelapses.isEmpty else { return 0 }
        let calendar = Calendar.current
        let studyDates = Set(myTimelapses.map { calendar.startOfDay(for: $0.createdAt) })
        var checkDate = calendar.startOfDay(for: Date())
        if !studyDates.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            if !studyDates.contains(checkDate) { return 0 }
        }
        var streak = 0
        while studyDates.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }
    
    private func quickStatsBar(user: UserProfile) -> some View {
        HStack(spacing: 0) {
            // Streak
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    Text("\(streakDays)")
                        .font(.gloucester(size: 20))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .offset(y: 1)
                }
                Text("streak")
                    .font(PigeonTheme.smallFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            
            // Record button
            Button {
                Haptics.medium()
                showingNewTimelapse = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("Record")
                        .font(PigeonTheme.subheadlineFont)
                        .fixedSize()
                        .offset(y: 1)
                }
                .foregroundStyle(PigeonTheme.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PigeonTheme.primaryText)
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .pigeonGlassSurface(cornerRadius: PigeonTheme.cornerCard)
    }
    
    private var sessionsThisWeek: Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return myTimelapses.filter { $0.createdAt >= weekStart }.count
    }
    
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 48)
            
            PigeonIcon(size: 56, color: PigeonTheme.tertiaryText)
                .padding(.bottom, PigeonTheme.spacing16)
            
            Text("the nest is empty")
                .font(.gloucester(size: 22))
                .foregroundStyle(PigeonTheme.primaryText)
                .padding(.bottom, PigeonTheme.spacing8)
            
            Text("Record a study session and\nwatch your nest fill up.")
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.bottom, PigeonTheme.spacing24)
            
            Button("Record a Session") {
                showingNewTimelapse = true
            }
            .buttonStyle(PigeonButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private func loadPublicFeed() async {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        do {
            let publicRows = try await SupabaseService.shared.fetchPublicFeed(excludeUID: uid)
            let existingIDs = Set(allTimelapses.map { $0.id })
            var inserted = 0
            let pendingDeletes = PendingDeleteStore.ids()
            for row in publicRows where !existingIDs.contains(row.id) && !pendingDeletes.contains(row.id.uuidString) {
                let timelapse = StudyTimelapse(
                    authorID: row.authorId.uuidString,
                    authorName: row.authorName,
                    authorAvatarURL: row.authorAvatarUrl,
                    caption: row.caption,
                    studyDescription: row.studyDescription,
                    subject: row.subject,
                    durationSeconds: row.durationSeconds,
                    isLandscape: row.isLandscape
                )
                timelapse.id = row.id
                timelapse.createdAt = row.createdAt
                timelapse.likeCount = row.likeCount
                timelapse.likedByUIDs = row.likedByUids
                timelapse.commentCount = row.commentCount
                timelapse.videoDownloadURL = row.videoDownloadUrl
                timelapse.thumbnailDownloadURL = row.thumbnailDownloadUrl
                if let segments = row.subjectSegmentsJson { timelapse.subjectSegmentsJSON = segments }
                if let leaves = row.appLeaveCount { timelapse.appLeaveCount = leaves }
                if let offTask = row.offTaskSeconds { timelapse.offTaskSeconds = offTask }
                timelapse.pigeonOrigin = row.pigeonOrigin
                timelapse.pigeonDestination = row.pigeonDestination
                timelapse.descriptionRarity = row.descriptionRarity
                modelContext.insert(timelapse)
                inserted += 1
            }
            publicAuthorUIDs = Array(Set(publicRows.map { $0.authorId.uuidString }))
            if inserted > 0 {
                print("[FEED] Inserted \(inserted) public timelapses into local store")
            }
        } catch {
            print("[FEED] Public feed fetch failed: \(error)")
        }
    }
}

// MARK: - Timelapse Card

struct TimelapseCardView: View {
    let timelapse: StudyTimelapse
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @Query private var users: [UserProfile]
    @State private var isLiked = false
    @State private var showDetail = false
    @State private var showDeleteConfirm = false
    @State private var cardPlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var cachedThumbnail: UIImage?
    @State private var cachedAfterPhoto: UIImage?
    @State private var showSubjectBreakdown = false
    @State private var showStoryStyleSheet = false
    @State private var showInstagramNotInstalled = false
    @State private var showHeartOverlay = false
    @State private var showShareSheet = false
    @State private var showEditSheet = false
    
    private var cardDescriptionRarity: PunRarity? {
        guard let raw = timelapse.descriptionRarity else { return nil }
        return PunRarity(rawValue: raw)
    }
    
    private var cardDescriptionColor: Color {
        guard let rarity = cardDescriptionRarity, rarity != .common else {
            return PigeonTheme.tertiaryText
        }
        return rarity.color
    }
    
    private var rarityTintColor: Color? {
        guard let rarity = cardDescriptionRarity, rarity != .common else { return nil }
        return rarity.color
    }
    
    private var isOwnPost: Bool {
        timelapse.authorID == AuthService.shared.currentUserID
    }
    
    /// For the current user's own posts, use the live profile name/avatar
    /// so edits propagate to old sessions immediately.
    private var displayName: String {
        if isOwnPost, let profile = users.first(where: { $0.firebaseUID == timelapse.authorID }) {
            return profile.displayName
        }
        return timelapse.authorName
    }
    
    private var displayAvatarURL: String? {
        if isOwnPost, let profile = users.first(where: { $0.firebaseUID == timelapse.authorID }) {
            return profile.avatarURL
        }
        return timelapse.authorAvatarURL
    }
    
    private var hasMedia: Bool {
        timelapse.videoFileName != nil || timelapse.thumbnailData != nil ||
        timelapse.videoDownloadURL != nil || timelapse.thumbnailDownloadURL != nil
    }
    
    /// Card height adapts to content: portrait ~4:5, landscape ~16:9, no-media ~2:1
    private var videoAspectRatio: CGFloat {
        if !hasMedia { return 2.0 }
        return timelapse.isLandscape ? 16.0 / 9.0 : 4.0 / 5.0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Author row — outside image, Strava-style
            HStack(spacing: 10) {
                avatarView(name: displayName, size: 40, avatarURL: displayAvatarURL)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    HStack(spacing: 6) {
                        Text(timelapse.createdAt.timeAgoDisplay())
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        
                        // Subject tag
                        if timelapse.hasMultipleSubjects {
                            Button {
                                Haptics.light()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showSubjectBreakdown.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(StudySubject.color(for: timelapse.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse])))
                                        .frame(width: 6, height: 6)
                                    Text(timelapse.subject)
                                        .font(PigeonTheme.smallFont)
                                    Image(systemName: showSubjectBreakdown ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .foregroundStyle(PigeonTheme.secondaryText)
                            }
                        } else {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(StudySubject.color(for: timelapse.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse])))
                                    .frame(width: 6, height: 6)
                                Text(timelapse.subject)
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.secondaryText)
                            }
                        }
                    }
                }
                
                Spacer()
                
                if isOwnPost {
                    Menu {
                        Button {
                            Haptics.light()
                            showEditSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            Haptics.warning()
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Multi-subject breakdown
            if showSubjectBreakdown {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(timelapse.subjectSegments) { segment in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(StudySubject.color(for: segment.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse])))
                                .frame(width: 8, height: 8)
                            Text(segment.subject)
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Text(formatSegmentDuration(segment.seconds))
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Caption as bold title (Strava style)
            Text(timelapse.caption)
                .font(.gloucester(size: 22))
                .foregroundStyle(PigeonTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.bottom, hasMedia ? 10 : 4)
            
            if !timelapse.studyDescription.isEmpty {
                HStack(spacing: 6) {
                    Text(timelapse.studyDescription)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(cardDescriptionColor)
                        .lineLimit(2)
                    
                    if let rarity = cardDescriptionRarity, rarity != .common {
                        Text(rarity.displayName)
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(rarity.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(rarity.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, hasMedia ? 10 : 4)
            }
            
            // Carrier Pigeon flight route
            if let origin = timelapse.pigeonOrigin, let dest = timelapse.pigeonDestination {
                HStack(spacing: 6) {
                    Image(systemName: "bird")
                        .font(.system(size: 11))
                    Text("\(origin) → \(dest)")
                        .font(PigeonTheme.smallFont)
                        .italic()
                }
                .foregroundStyle(PigeonTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.bottom, hasMedia ? 10 : 4)
            }
            
            // Media section
            if hasMedia {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = width / videoAspectRatio
                    
                    ZStack(alignment: .bottomTrailing) {
                        if let cardPlayer {
                            FillVideoPlayerView(player: cardPlayer)
                                .frame(width: width, height: height)
                                .allowsHitTesting(false)
                        } else if let uiImage = cachedThumbnail {
                            if let afterImage = cachedAfterPhoto {
                                TabView {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: width, height: height)
                                        .clipped()
                                    Image(uiImage: afterImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: width, height: height)
                                        .clipped()
                                }
                                .tabViewStyle(.page(indexDisplayMode: .always))
                                .frame(width: width, height: height)
                            } else {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: width, height: height)
                                    .clipped()
                            }
                        }
                        
                        // Duration badge
                        Text(timelapse.formattedDuration)
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                    .frame(width: width, height: height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        doubleTapLike()
                    }
                    .overlay {
                        if showHeartOverlay {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                }
                .aspectRatio(videoAspectRatio, contentMode: .fit)
                .onAppear {
                    if let cardPlayer {
                        cardPlayer.play()
                    } else {
                        setupCardPlayer()
                    }
                }
                .onDisappear {
                    cardPlayer?.pause()
                    playerLooper = nil
                    cardPlayer = nil
                }
            }
            
            // Stats row (Strava-style: Duration | Subject | Focus)
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(timelapse.formattedDuration)
                        .font(.gloucester(size: 18))
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text("Duration")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(PigeonTheme.separator)
                    .frame(width: 1, height: 28)
                
                VStack(spacing: 2) {
                    Text(timelapse.subject)
                        .font(.gloucester(size: 18))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .lineLimit(1)
                    Text("Subject")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                
                if timelapse.appLeaveCount > 0 {
                    Rectangle()
                        .fill(PigeonTheme.separator)
                        .frame(width: 1, height: 28)
                    
                    VStack(spacing: 2) {
                        Text("\(timelapse.appLeaveCount)")
                            .font(.gloucester(size: 18))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("Left App")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            
            // Thin separator
            Rectangle()
                .fill(PigeonTheme.separator)
                .frame(height: 1)
                .padding(.horizontal, 14)
            
            // Action bar
            HStack(spacing: 24) {
                Button {
                    Haptics.light()
                    let uid = AuthService.shared.currentUserID
                    guard !uid.isEmpty else { return }
                    withAnimation(.spring(response: 0.3)) {
                        isLiked.toggle()
                    }
                    if isLiked {
                        if !timelapse.likedByUIDs.contains(uid) {
                            timelapse.likedByUIDs.append(uid)
                            timelapse.likeCount += 1
                        }
                    } else {
                        timelapse.likedByUIDs.removeAll { $0 == uid }
                        timelapse.likeCount = max(0, timelapse.likeCount - 1)
                    }
                    Task {
                        try? await SupabaseService.shared.toggleLike(
                            timelapseID: timelapse.id.uuidString,
                            userUID: uid,
                            isLiked: isLiked
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? PigeonTheme.destructive : PigeonTheme.secondaryText)
                        Text("\(timelapse.likeCount)")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }

                Menu {
                    Button {
                        Haptics.light()
                        showShareSheet = true
                    } label: {
                        Label("Share Link", systemImage: "link")
                    }
                    
                    Button {
                        Haptics.light()
                        guard InstagramStoriesSharer.isInstagramInstalled else {
                            showInstagramNotInstalled = true
                            return
                        }
                        showStoryStyleSheet = true
                    } label: {
                        Label("Instagram Story", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .modifier(PigeonGlassPostModifier(tint: rarityTintColor))
        .contentShape(Rectangle())
        .onTapGesture {
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            TimelapseDetailView(timelapse: timelapse)
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteTimelapse()
            }
        } message: {
            Text("This session will fly away forever. No coming back to the nest.")
        }
        .alert("Instagram Not Installed", isPresented: $showInstagramNotInstalled) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This pigeon can't deliver without Instagram. Install it first!")
        }
        .sheet(isPresented: $showShareSheet) {
            let shareURL = URL(string: "https://pigeonstudy.ing/nest?post=\(timelapse.id.uuidString.lowercased())")!
            let shareText = "I studied \(timelapse.formattedDuration) of \(timelapse.subject) on Pigeon"
            ShareSheet(items: [shareText, shareURL])
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showStoryStyleSheet) {
            let color = StudySubject.color(for: timelapse.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse]))
            let colorResolver: (String) -> Color = { name in
                StudySubject.color(for: name, in: subjects, hexes: StudySubject.hexes(in: [timelapse]))
            }
            StickerCanvasView(
                durationSeconds: timelapse.durationSeconds,
                subjectName: timelapse.subject,
                subjectColor: color,
                appLeaveCount: timelapse.appLeaveCount,
                caption: timelapse.caption,
                studyDescription: timelapse.studyDescription,
                subjectSegments: timelapse.subjectSegments,
                subjectColorResolver: colorResolver,
                videoURL: timelapse.videoURL,
                thumbnailData: timelapse.thumbnailData,
                sessionDate: timelapse.createdAt,
                onExport: {}
            )
        }
        .sheet(isPresented: $showEditSheet) {
            EditPostSheet(timelapse: timelapse)
        }
        .onAppear {
            let uid = AuthService.shared.currentUserID
            isLiked = timelapse.likedByUIDs.contains(uid)
            if cachedThumbnail == nil, let data = timelapse.thumbnailData {
                let thumbData = data
                Task.detached {
                    let image = UIImage(data: thumbData)
                    await MainActor.run { cachedThumbnail = image }
                }
            } else if cachedThumbnail == nil, timelapse.thumbnailData == nil,
                      let thumbURLString = timelapse.thumbnailDownloadURL,
                      let thumbURL = URL(string: thumbURLString) {
                Task.detached {
                    if let (data, _) = try? await URLSession.shared.data(from: thumbURL),
                       let image = UIImage(data: data) {
                        await MainActor.run { cachedThumbnail = image }
                    }
                }
            }
            if cachedAfterPhoto == nil, let data = timelapse.afterPhotoData {
                let afterData = data
                Task.detached {
                    let image = UIImage(data: afterData)
                    await MainActor.run { cachedAfterPhoto = image }
                }
            }
        }
    }
    
    private func doubleTapLike() {
        Haptics.medium()
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        // Only add a like, never remove on double-tap (Instagram behavior)
        if !isLiked {
            withAnimation(.spring(response: 0.3)) {
                isLiked = true
            }
            if !timelapse.likedByUIDs.contains(uid) {
                timelapse.likedByUIDs.append(uid)
                timelapse.likeCount += 1
            }
            Task {
                try? await SupabaseService.shared.toggleLike(
                    timelapseID: timelapse.id.uuidString,
                    userUID: uid,
                    isLiked: true
                )
            }
        }
        // Show heart overlay animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showHeartOverlay = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                showHeartOverlay = false
            }
        }
    }
    
    private func deleteTimelapse() {
        // Stop playback
        cardPlayer?.pause()
        cardPlayer = nil
        playerLooper = nil
        
        // Capture info before deleting
        let timelapseID = timelapse.id
        let authorID = timelapse.authorID
        
        // Delete local video file
        if let videoURL = timelapse.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        
        // Delete from SwiftData and persist immediately
        modelContext.delete(timelapse)
        do {
            try modelContext.save()
        } catch {
            print("[DELETE] Local delete save failed: \(error.localizedDescription)")
        }
        
        // Track pending cloud delete so syncTimelapses won't re-insert
        PendingDeleteStore.add(timelapseID)
        
        // Delete from Supabase (cloud DB + storage files)
        Task {
            do {
                try await SupabaseService.shared.deleteTimelapse(timelapseID)
                // Cloud delete succeeded — remove from pending list
                PendingDeleteStore.remove(timelapseID)
            } catch {
                print("[DELETE] Cloud delete failed (will retry on next sync): \(error)")
            }
            await StorageService.shared.deleteTimelapseFiles(
                userUID: authorID,
                timelapseID: timelapseID.uuidString
            )
        }
    }
    
    private func setupCardPlayer() {
        guard let url = timelapse.videoURL else {
            print("[VIDEO] Card player: no URL for timelapse \(timelapse.id.uuidString.prefix(8)) — videoDownloadURL: \(timelapse.videoDownloadURL ?? "nil")")
            return
        }
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        cardPlayer = queuePlayer
        playerLooper = looper
        queuePlayer.play()
    }
}

// MARK: - Timelapse Detail View

struct TimelapseDetailView: View {
    let timelapse: StudyTimelapse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var player: AVPlayer?
    @State private var isLiked = false
    @State private var cachedThumbnail: UIImage?
    @State private var cachedAfterPhoto: UIImage?
    @State private var showInstagramNotInstalled = false
    @State private var showStoryStyleSheet = false
    @State private var showShareSheet = false
    @State private var showEditSheet = false
    
    private var currentUserName: String {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }?.displayName ?? "You"
    }
    
    private var isOwnPost: Bool {
        timelapse.authorID == AuthService.shared.currentUserID
    }
    
    private var detailDisplayName: String {
        if isOwnPost, let profile = users.first(where: { $0.firebaseUID == timelapse.authorID }) {
            return profile.displayName
        }
        return timelapse.authorName
    }
    
    private var detailDisplayAvatarURL: String? {
        if isOwnPost, let profile = users.first(where: { $0.firebaseUID == timelapse.authorID }) {
            return profile.avatarURL
        }
        return timelapse.authorAvatarURL
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Timelapse video player or photo
                    ZStack {
                        if let player {
                            FillVideoPlayerView(player: player)
                        } else if let uiImage = cachedThumbnail {
                            if let afterImage = cachedAfterPhoto {
                                // Before/after carousel
                                TabView {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                    Image(uiImage: afterImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                                .tabViewStyle(.page(indexDisplayMode: .always))
                            } else {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        } else {
                            // No-media — show session stats
                            Rectangle()
                                .fill(PigeonTheme.surfaceBackground)
                                .overlay(
                                    HStack(spacing: 24) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 20))
                                                .frame(height: 22)
                                                .foregroundStyle(PigeonTheme.accent)
                                            Text(timelapse.formattedDuration)
                                                .font(PigeonTheme.font(16, weight: .bold))
                                                .frame(height: 20)
                                                .foregroundStyle(PigeonTheme.primaryText)
                                            Text("Duration")
                                                .font(PigeonTheme.smallFont)
                                                .frame(height: 14)
                                                .foregroundStyle(PigeonTheme.tertiaryText)
                                        }
                                        
                                        Rectangle()
                                            .fill(PigeonTheme.separator)
                                            .frame(width: 1, height: 44)
                                        
                                        VStack(spacing: 6) {
                                            Image(systemName: "book.fill")
                                                .font(.system(size: 20))
                                                .frame(height: 22)
                                                .foregroundStyle(StudySubject.color(for: timelapse.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse])))
                                            Text(timelapse.subject)
                                                .font(PigeonTheme.font(16, weight: .bold))
                                                .frame(height: 20)
                                                .foregroundStyle(PigeonTheme.primaryText)
                                                .lineLimit(1)
                                            Text("Subject")
                                                .font(PigeonTheme.smallFont)
                                                .frame(height: 14)
                                                .foregroundStyle(PigeonTheme.tertiaryText)
                                        }
                                        
                                        if timelapse.appLeaveCount > 0 {
                                            Rectangle()
                                                .fill(PigeonTheme.separator)
                                                .frame(width: 1, height: 44)
                                            
                                            VStack(spacing: 6) {
                                                Image(systemName: "iphone.and.arrow.forward")
                                                    .font(.system(size: 20))
                                                    .frame(height: 22)
                                                    .foregroundStyle(.red.opacity(0.7))
                                                Text("\(timelapse.appLeaveCount)")
                                                    .font(PigeonTheme.font(16, weight: .bold))
                                                    .frame(height: 20)
                                                    .foregroundStyle(PigeonTheme.primaryText)
                                                Text("Left App")
                                                    .font(PigeonTheme.smallFont)
                                                    .frame(height: 14)
                                                    .foregroundStyle(PigeonTheme.tertiaryText)
                                            }
                                        }
                                    }
                                    .padding(.top, 16)
                                )
                        }
                    }
                    .aspectRatio({
                        let hasMedia = timelapse.videoFileName != nil || timelapse.thumbnailData != nil ||
                            timelapse.videoDownloadURL != nil || timelapse.thumbnailDownloadURL != nil
                        if !hasMedia { return 2.0 }
                        return timelapse.isLandscape ? 16.0 / 9.0 : 9.0 / 16.0
                    }(), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Author info
                    HStack(spacing: 12) {
                        avatarView(name: detailDisplayName, size: 44, avatarURL: detailDisplayAvatarURL)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detailDisplayName)
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Text(timelapse.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    }
                    
                    // Caption
                    Text(timelapse.caption)
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    // Subject(s)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "book.fill")
                                .foregroundStyle(PigeonTheme.secondaryText)
                            Text(timelapse.subject)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                        if timelapse.hasMultipleSubjects {
                            ForEach(timelapse.subjectSegments) { segment in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(StudySubject.color(for: segment.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse])))
                                        .frame(width: 8, height: 8)
                                    Text(segment.subject)
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.primaryText)
                                    Spacer()
                                    Text(formatSegmentDuration(segment.seconds))
                                        .font(PigeonTheme.captionFont)
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                }
                                .padding(.leading, 24)
                            }
                        }
                    }
                    
                    // Description
                    if !timelapse.studyDescription.isEmpty {
                        Text(timelapse.studyDescription)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .lineSpacing(4)
                    }
                    
                    // Carrier Pigeon flight route
                    if let origin = timelapse.pigeonOrigin, let dest = timelapse.pigeonDestination {
                        HStack(spacing: 6) {
                            Image(systemName: "bird")
                                .font(.system(size: 13))
                            Text("\(origin) → \(dest)")
                                .font(PigeonTheme.bodyFont)
                                .italic()
                        }
                        .foregroundStyle(PigeonTheme.secondaryText)
                    }
                    
                    // Like button
                    HStack(spacing: 20) {
                        Button {
                            Haptics.light()
                            let uid = AuthService.shared.currentUserID
                            guard !uid.isEmpty else { return }
                            withAnimation(.spring(response: 0.3)) {
                                isLiked.toggle()
                            }
                            if isLiked {
                                if !timelapse.likedByUIDs.contains(uid) {
                                    timelapse.likedByUIDs.append(uid)
                                    timelapse.likeCount += 1
                                }
                            } else {
                                timelapse.likedByUIDs.removeAll { $0 == uid }
                                timelapse.likeCount = max(0, timelapse.likeCount - 1)
                            }
                            Task {
                                try? await SupabaseService.shared.toggleLike(
                                    timelapseID: timelapse.id.uuidString,
                                    userUID: uid,
                                    isLiked: isLiked
                                )
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isLiked ? PigeonTheme.destructive : PigeonTheme.secondaryText)
                                Text("\(timelapse.likeCount)")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button {
                                Haptics.light()
                                showShareSheet = true
                            } label: {
                                Label("Share Link", systemImage: "link")
                            }
                            
                            Button {
                                Haptics.light()
                                guard InstagramStoriesSharer.isInstagramInstalled else {
                                    showInstagramNotInstalled = true
                                    return
                                }
                                showStoryStyleSheet = true
                            } label: {
                                Label("Instagram Story", systemImage: "camera")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    }
                    
                    Divider()
                        .background(PigeonTheme.separator)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PigeonTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
                if isOwnPost {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Haptics.light()
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(PigeonTheme.accent)
                        }
                    }
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Instagram Not Found", isPresented: $showInstagramNotInstalled) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Install Instagram to share your study stats to your Story.")
            }
            .sheet(isPresented: $showShareSheet) {
                let shareURL = URL(string: "https://pigeonstudy.ing/nest?post=\(timelapse.id.uuidString.lowercased())")!
                let shareText = "I studied \(timelapse.formattedDuration) of \(timelapse.subject) on Pigeon"
                ShareSheet(items: [shareText, shareURL])
                    .presentationDetents([.medium])
            }
            .fullScreenCover(isPresented: $showStoryStyleSheet) {
                let color = StudySubject.color(for: timelapse.subject, in: subjects, hexes: StudySubject.hexes(in: [timelapse]))
                let colorResolver: (String) -> Color = { name in
                    StudySubject.color(for: name, in: subjects, hexes: StudySubject.hexes(in: [timelapse]))
                }
                StickerCanvasView(
                    durationSeconds: timelapse.durationSeconds,
                    subjectName: timelapse.subject,
                    subjectColor: color,
                    appLeaveCount: timelapse.appLeaveCount,
                    caption: timelapse.caption,
                    studyDescription: timelapse.studyDescription,
                    subjectSegments: timelapse.subjectSegments,
                    subjectColorResolver: colorResolver,
                    videoURL: timelapse.videoURL,
                    thumbnailData: timelapse.thumbnailData,
                    sessionDate: timelapse.createdAt,
                    onExport: {}
                )
            }
            .sheet(isPresented: $showEditSheet) {
                EditPostSheet(timelapse: timelapse)
            }
            .onAppear {
                let uid = AuthService.shared.currentUserID
                isLiked = timelapse.likedByUIDs.contains(uid)
                if cachedThumbnail == nil, let data = timelapse.thumbnailData {
                    let thumbData = data
                    Task.detached {
                        let image = UIImage(data: thumbData)
                        await MainActor.run { cachedThumbnail = image }
                    }
                } else if cachedThumbnail == nil, timelapse.thumbnailData == nil,
                          let thumbURLString = timelapse.thumbnailDownloadURL,
                          let thumbURL = URL(string: thumbURLString) {
                    Task.detached {
                        if let (data, _) = try? await URLSession.shared.data(from: thumbURL),
                           let image = UIImage(data: data) {
                            await MainActor.run { cachedThumbnail = image }
                        }
                    }
                }
                if cachedAfterPhoto == nil, let data = timelapse.afterPhotoData {
                    let afterData = data
                    Task.detached {
                        let image = UIImage(data: afterData)
                        await MainActor.run { cachedAfterPhoto = image }
                    }
                }
                
                if let url = timelapse.videoURL {
                    print("[VIDEO] Detail: playing from \(url.scheme == "file" ? "local" : "cloud") URL")
                    let avPlayer = AVPlayer(url: url)
                    player = avPlayer
                    avPlayer.play()
                } else {
                    print("[VIDEO] Detail: no URL — videoDownloadURL: \(timelapse.videoDownloadURL ?? "nil"), videoFileName: \(timelapse.videoFileName ?? "nil")")
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
        .presentationBackground(PigeonTheme.background)
    }
}

// MARK: - Helpers

func avatarView(name: String, size: CGFloat, avatarURL: String? = nil) -> some View {
    let initial = String(name.prefix(1)).uppercased()
    let localImage: UIImage? = {
        guard let avatarURL, let url = URL(string: avatarURL) else { return nil }
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }()
    return Group {
        if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let avatarURL, let url = URL(string: avatarURL), !url.isFileURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                default:
                    Circle()
                        .fill(PigeonTheme.elevated)
                        .frame(width: size, height: size)
                        .overlay(
                            Text(initial)
                                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                                .foregroundStyle(PigeonTheme.primaryText)
                        )
                }
            }
        } else {
            Circle()
                .fill(PigeonTheme.elevated)
                .frame(width: size, height: size)
                .overlay(
                    Text(initial)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(PigeonTheme.primaryText)
                )
        }
    }
}

private func formatSegmentDuration(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
    return "\(seconds)s"
}

extension Date {
    func timeAgoDisplay() -> String {
        let seconds = -self.timeIntervalSinceNow
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        return "\(weeks)w ago"
    }
}

// MARK: - Edit Post Sheet

struct EditPostSheet: View {
    let timelapse: StudyTimelapse
    @Environment(\.dismiss) private var dismiss
    @State private var editedCaption: String = ""
    @State private var editedDescription: String = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $editedCaption)
                        .font(PigeonTheme.bodyFont)
                }
                
                Section("Description") {
                    TextField("Description (optional)", text: $editedDescription, axis: .vertical)
                        .font(PigeonTheme.bodyFont)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PigeonTheme.background)
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveEdits()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(editedCaption.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .foregroundStyle(PigeonTheme.accent)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .onAppear {
            editedCaption = timelapse.caption
            editedDescription = timelapse.studyDescription
        }
    }
    
    private func saveEdits() {
        let newCaption = editedCaption.trimmingCharacters(in: .whitespaces)
        let newDescription = editedDescription.trimmingCharacters(in: .whitespaces)
        guard !newCaption.isEmpty else { return }
        
        isSaving = true
        
        // Update local SwiftData model
        timelapse.caption = newCaption
        timelapse.studyDescription = newDescription
        
        // Sync to Supabase
        let timelapseID = timelapse.id
        Task {
            do {
                try await SupabaseService.shared.updateTimelapseText(
                    id: timelapseID,
                    caption: newCaption,
                    studyDescription: newDescription
                )
            } catch {
                print("[EDIT] Failed to sync edit to Supabase: \(error)")
            }
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

// MARK: - Fill Video Player (AVPlayerLayer-based, no black bars)

struct FillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let v = uiView as? PlayerLayerView {
            v.playerLayer.player = player
        }
    }

    private class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
