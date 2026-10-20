//
//  ProfileView.swift
//  Pigeon
//
//  User profile view with stats and Google sign-in
//

import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var showSignIn = false
    @State private var showEditProfile = false
    @State private var showSettings = false
    @State private var showRecaps = false
    @State private var appeared = false
    @State private var showAddSubject = false
    @State private var subjectToEdit: StudySubject? = nil
    @State private var showShareSheet = false
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var userTimelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid }
    }
    
    @State private var profileTab = 0 // 0 = Progress, 1 = Sessions
    private let profileTabs = [0, 1]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Top bar: "You" title left, settings gear right (Strava style)
                    HStack {
                        Text("You")
                            .font(PigeonTheme.titleFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Spacer()
                        
                        Button {
                            Haptics.medium()
                            showRecaps = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(PigeonTheme.secondaryText)
                                .frame(width: 36, height: 36)
                        }
                        
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(PigeonTheme.secondaryText)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, PigeonTheme.spacing8)
                    .staggeredAppear(index: 0, appeared: appeared)
                    
                    if let user = currentUser {
                        profileHeader(user: user)
                            .padding(.bottom, PigeonTheme.spacing16)
                            .staggeredAppear(index: 1, appeared: appeared)
                        
                        // Underline tab picker (Strava style)
                        PigeonUnderlinePicker(
                            tabs: profileTabs,
                            selection: $profileTab,
                            label: { $0 == 0 ? "Progress" : "Sessions" }
                        )
                        .padding(.bottom, PigeonTheme.spacing16)
                        .staggeredAppear(index: 2, appeared: appeared)
                        
                        // Tab content
                        Group {
                            if profileTab == 0 {
                                progressTab(user: user)
                            } else {
                                myPostsSection
                            }
                        }
                        .staggeredAppear(index: 3, appeared: appeared)
                    } else if AuthService.shared.isSignedIn {
                        VStack(spacing: 16) {
                            Spacer().frame(height: 80)
                            ProgressView()
                                .tint(PigeonTheme.accent)
                            Text("Loading profile…")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    } else {
                        signInPrompt
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .pigeonWallpaper()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { withAnimation { appeared = true } }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showRecaps) {
                if let user = currentUser {
                    RecapsView(
                        displayName: user.displayName,
                        allTimelapses: userTimelapses
                    )
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let user = currentUser {
                    let profileLink = profileShareURL(for: user)
                    ShareProfileSheet(url: profileLink, displayName: user.displayName)
                }
            }
            .task {
                guard let user = currentUser else { return }
                let newMinutes = computedTotalStudyMinutes
                let newStreak = computedStreakDays
                if user.totalStudyMinutes != newMinutes || user.streakDays != newStreak {
                    user.totalStudyMinutes = newMinutes
                    user.streakDays = newStreak
                    try? await SupabaseService.shared.saveUserProfile(user)
                }
            }
        }
    }
    
    // MARK: - Profile Header
    
    private func profileHeader(user: UserProfile) -> some View {
        VStack(spacing: 14) {
            // Avatar + name side by side
            HStack(spacing: 14) {
                avatarView(name: user.displayName, size: 64, avatarURL: user.avatarURL)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                        .font(PigeonTheme.titleFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.accent)
                    }
                    
                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .lineLimit(2)
                    }
                    
                }
                
                Spacer()
                
                Button {
                    showEditProfile = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .padding(12)
                        .pigeonGlassSurface(cornerRadius: 20)
                }
            }
            
            // Friend count + share profile on one line
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("\(user.friendUIDs.count)")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text("friend\(user.friendUIDs.count == 1 ? "" : "s")")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Spacer()
                
                Button {
                    Haptics.light()
                    showShareSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .medium))
                        Text("Share Profile")
                            .font(PigeonTheme.captionFont)
                    }
                    .foregroundStyle(PigeonTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .pigeonGlassSurface(cornerRadius: 10)
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Computed Stats
    
    /// All-time total study minutes computed from every session
    private var computedTotalStudyMinutes: Int {
        userTimelapses.reduce(0) { $0 + $1.durationSeconds } / 60
    }
    
    /// Top 3 subjects by total study time (name + minutes)
    private var computedTopSubjects: [(name: String, minutes: Int)] {
        var dict: [String: Int] = [:]
        for tl in userTimelapses {
            for seg in tl.subjectSegments {
                dict[seg.subject, default: 0] += seg.seconds
            }
        }
        return dict.map { ($0.key, $0.value / 60) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0 }
    }
    
    /// Streak: consecutive calendar days (ending today or yesterday) with at least one session
    private var computedStreakDays: Int {
        guard !userTimelapses.isEmpty else { return 0 }
        let calendar = Calendar.current
        // Get unique study dates (start of day)
        let studyDates = Set(userTimelapses.map { calendar.startOfDay(for: $0.createdAt) })
        let today = calendar.startOfDay(for: Date())
        
        // Start counting from today; if no session today, try yesterday
        var checkDate = today
        if !studyDates.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            if !studyDates.contains(checkDate) {
                return 0
            }
        }
        
        var streak = 0
        while studyDates.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }
    
    // MARK: - Progress Tab (Strava-style)
    
    private func progressTab(user: UserProfile) -> some View {
        let totalHours = computedTotalStudyMinutes / 60
        let totalMins = computedTotalStudyMinutes % 60
        let longestMinutes = (userTimelapses.max(by: { $0.durationSeconds < $1.durationSeconds })?.durationSeconds ?? 0) / 60
        let mostInADayMinutes = computedMostInADay / 60
        
        return VStack(spacing: 20) {
            // Stats row (Strava-style: large values, small labels, dividers)
            PigeonStatRow(stats: [
                (value: "\(totalHours)h \(totalMins)m", label: "Total Time"),
                (value: "\(userTimelapses.count)", label: "Sessions"),
                (value: "\(computedStreakDays)", label: "Streak")
            ])
            
            // Detailed stats + Your Flock side by side
            HStack(spacing: 12) {
                NavigationLink {
                    StatsView()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(PigeonTheme.accent)
                        Text("Stats")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("charts & trends")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .pigeonGlassCard()
                }
                .overlay {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: StatsCardFrameKey.self,
                            value: geo.frame(in: .global)
                        )
                    }
                }
                
                NavigationLink {
                    FriendsView()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(PigeonTheme.accent)
                        Text("Your Flock")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("manage friends")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .pigeonGlassCard()
                }
            }
            
            // Top subjects
            if !computedTopSubjects.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TOP SUBJECTS")
                        .pigeonSectionTitle()
                    
                    ForEach(computedTopSubjects, id: \.name) { subject in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(StudySubject.color(for: subject.name, in: subjects))
                                .frame(width: 8, height: 8)
                            Text(subject.name)
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Text("\(subject.minutes / 60)h \(subject.minutes % 60)m")
                                .font(.gloucester(size: 14))
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .pigeonGlassSurface(cornerRadius: 12)
                    }
                }
                .padding(.top, 4)
            }
            
            // Personal records
            VStack(alignment: .leading, spacing: 10) {
                Text("PERSONAL RECORDS")
                    .pigeonSectionTitle()
                
                HStack(spacing: 10) {
                    VStack(spacing: 4) {
                        Text("\(longestMinutes / 60)h \(longestMinutes % 60)m")
                            .font(.gloucester(size: 18))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("Longest Session")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .pigeonGlassSurface(cornerRadius: 12)
                    
                    VStack(spacing: 4) {
                        Text("\(mostInADayMinutes / 60)h \(mostInADayMinutes % 60)m")
                            .font(.gloucester(size: 18))
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text("Most in a Day")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .pigeonGlassSurface(cornerRadius: 12)
                }
            }
            .padding(.top, 4)
            
            // Subjects
            subjectsSection
        }
    }
    
    /// Most minutes studied in a single calendar day
    private var computedMostInADay: Int {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: userTimelapses) { calendar.startOfDay(for: $0.createdAt) }
        let maxSeconds = byDay.values.map { $0.reduce(0) { $0 + $1.durationSeconds } }.max() ?? 0
        return maxSeconds / 60
    }
    
    // MARK: - Subjects Section
    
    private var subjectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR SUBJECTS")
                    .pigeonSectionTitle()
                Spacer()
                NavigationLink {
                    ManageSubjectsView()
                } label: {
                    Text("Edit")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.accent)
                }
            }
            
            if subjects.isEmpty {
                Text("No subjects yet. Tap Edit to add some.")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .padding(.vertical, 8)
            } else {
                // Wrap subjects as colored pills
                WrappingHStack(items: subjects) { subject in
                    Button {
                        subjectToEdit = subject
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(subject.color)
                                .frame(width: 8, height: 8)
                            Text(subject.name)
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .pigeonGlassSurface(cornerRadius: 16)
                    }
                }
            }
            
            Button {
                Haptics.light()
                showAddSubject = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("Add Subject")
                        .font(PigeonTheme.captionFont)
                }
                .foregroundStyle(PigeonTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .pigeonGlassSurface(cornerRadius: 16)
            }
        }
        .padding(.top, 4)
        .sheet(isPresented: $showAddSubject) {
            AddSubjectView()
        }
        .sheet(item: $subjectToEdit) { subject in
            EditSubjectView(subject: subject)
        }
    }
    
    // MARK: - My Posts
    
    private var myPostsSection: some View {
        VStack(alignment: .leading, spacing: PigeonTheme.spacing12) {
            Text("My Sessions")
                .pigeonSectionTitle()
            
            if userTimelapses.isEmpty {
                Text("Your recorded sessions will appear here.")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PigeonTheme.spacing16)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(userTimelapses) { timelapse in
                        TimelapseCardView(timelapse: timelapse)
                    }
                }
            }
        }
    }
    
    // MARK: - Sign In Prompt
    
    // MARK: - Share Profile
    
    private func profileShareURL(for user: UserProfile) -> URL {
        // Use username if available, otherwise fall back to firebaseUID
        let identifier = user.username ?? user.firebaseUID ?? user.id.uuidString
        return URL(string: "https://pigeonstudy.ing/\(identifier)")!
    }
    
    private var signInPrompt: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)
            
            PigeonIcon(size: 112, color: PigeonTheme.secondaryText)
            
            Text("Welcome to Pigeon")
                .font(PigeonTheme.titleFont)
                .foregroundStyle(PigeonTheme.primaryText)
            
            Text("Sign in to track your study sessions\nand connect with friends")
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            // Google Sign-In button
            Button {
                Haptics.medium()
                Task {
                    try? await AuthService.shared.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 22))
                    Text("Sign in with Google")
                        .font(PigeonTheme.subheadlineFont)
                }
                .foregroundStyle(PigeonTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Share Profile Sheet

/// Shows a compact link preview popup with copy and share options.
struct ShareProfileSheet: View {
    let url: URL
    let displayName: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showSystemShare = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Drag indicator
            Capsule()
                .fill(PigeonTheme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            
            // Link preview
            HStack(spacing: 12) {
                PigeonIcon(size: 32, color: PigeonTheme.accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    Text(url.absoluteString)
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.accent)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(14)
            .background(PigeonTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Action buttons side by side
            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    UIPasteboard.general.url = url
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                        Text(copied ? "Copied!" : "Copy Link")
                            .font(PigeonTheme.captionFont)
                    }
                    .foregroundStyle(PigeonTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(PigeonTheme.separator, lineWidth: 1)
                    )
                }
                
                Button {
                    Haptics.medium()
                    showSystemShare = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                        Text("Share")
                            .font(PigeonTheme.captionFont)
                    }
                    .foregroundStyle(PigeonTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PigeonTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(PigeonTheme.background)
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(PigeonTheme.background)
        .sheet(isPresented: $showSystemShare) {
            SystemShareSheet(url: url, displayName: displayName)
        }
    }
}

/// Wraps UIActivityViewController for the native iOS share sheet.
private struct SystemShareSheet: UIViewControllerRepresentable {
    let url: URL
    let displayName: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let text = "Check out \(displayName)'s study profile on Pigeon"
        let controller = UIActivityViewController(
            activityItems: [text, url],
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var displayName = ""
    @State private var bio = ""
    @State private var username = ""
    @State private var originalUsername = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImageData: Data?
    @State private var isPrivateAccount = true

    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var usernameChanged: Bool {
        username != originalUsername
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                // Avatar with photo picker
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let avatarImageData, let uiImage = UIImage(data: avatarImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else if let avatarURL = currentUser?.avatarURL, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                default:
                                    Circle()
                                        .fill(PigeonTheme.elevated)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(PigeonTheme.secondaryText)
                                        )
                                }
                            }
                        } else {
                            Circle()
                                .fill(PigeonTheme.elevated)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                )
                        }
                        
                        Circle()
                            .fill(PigeonTheme.accent)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(PigeonTheme.accentText)
                            )
                    }
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            avatarImageData = data
                        }
                    }
                }
                .padding(.top, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    
                    TextField("Your name", text: $displayName)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .tint(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    
                    HStack(spacing: 4) {
                        Text("@")
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        TextField("username", text: $username)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                let sanitized = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                if sanitized != newValue { username = sanitized }
                                // If reverted to original, no need to check
                                if sanitized == originalUsername {
                                    usernameAvailable = nil
                                    isCheckingUsername = false
                                    usernameCheckTask?.cancel()
                                    return
                                }
                                usernameAvailable = nil
                                usernameCheckTask?.cancel()
                                guard sanitized.count >= 3 else { return }
                                usernameCheckTask = Task {
                                    isCheckingUsername = true
                                    try? await Task.sleep(for: .milliseconds(400))
                                    guard !Task.isCancelled else { return }
                                    usernameAvailable = try? await SupabaseService.shared.isUsernameAvailable(sanitized)
                                    isCheckingUsername = false
                                }
                            }
                    }
                    .padding(14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                usernameChanged && usernameAvailable == true ? Color.green.opacity(0.5) :
                                usernameChanged && usernameAvailable == false ? PigeonTheme.destructive.opacity(0.5) :
                                Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    
                    if isCheckingUsername {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Checking...")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                    } else if usernameChanged, let available = usernameAvailable {
                        Text(available ? "Username available" : "Username taken")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(available ? .green : PigeonTheme.destructive)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    
                    TextField("Tell people about yourself", text: $bio)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Account privacy toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private Account")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        Text(isPrivateAccount
                             ? "Only friends can see your sessions"
                             : "Anyone can see your sessions in the feed")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                    Spacer()
                    Toggle("", isOn: $isPrivateAccount)
                        .labelsHidden()
                        .tint(PigeonTheme.accent)
                }
                .padding(14)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            }
            .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PigeonTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Profile")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let user = currentUser else { return }
                        user.displayName = displayName
                        user.bio = bio
                        user.isPrivate = isPrivateAccount
                        
                        // Save avatar locally (MVP: no cloud upload)
                        if let avatarImageData {
                            let fileName = "avatar_\(user.firebaseUID ?? user.id.uuidString).jpg"
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let avatarPath = docs.appendingPathComponent(fileName)
                            try? avatarImageData.write(to: avatarPath)
                            user.avatarURL = avatarPath.absoluteString
                        }
                        
                        // Handle username change
                        let newUsername = username.lowercased()
                        let needsUsernameClaim = usernameChanged && newUsername.count >= 3 && usernameAvailable == true
                        
                        // Sync profile changes to Supabase
                        Task {
                            if needsUsernameClaim {
                                let uid = AuthService.shared.currentUserID
                                let claimed = try? await SupabaseService.shared.claimUsername(newUsername, forUser: uid)
                                if claimed == true {
                                    await MainActor.run {
                                        user.username = newUsername
                                    }
                                }
                            }
                            try? await SupabaseService.shared.saveUserProfile(user)
                        }
                        
                        dismiss()
                    }
                    .foregroundStyle(PigeonTheme.accent)
                    .font(PigeonTheme.font(15, weight: .semibold))
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
        .onAppear {
            if let user = currentUser {
                displayName = user.displayName
                bio = user.bio
                username = user.username ?? ""
                originalUsername = user.username ?? ""
                isPrivateAccount = user.isPrivate
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var users: [UserProfile]
    @State private var googlePhotosBackup = GooglePhotosService.shared.isBackupEnabled
    @State private var isRequestingScope = false
    @State private var showScopeError = false
    @State private var scopeErrorMessage = ""
    /// 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("autoDimScreen") private var autoDimScreen = false
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsPlaceholderView(title: "Notifications")
                    } label: {
                        settingsRow(icon: "bell.fill", title: "Notifications")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    NavigationLink {
                        SettingsPlaceholderView(title: "Privacy")
                    } label: {
                        settingsRow(icon: "lock.fill", title: "Privacy")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)

                    NavigationLink {
                        WallpaperPickerView(mode: .home)
                    } label: {
                        settingsRow(icon: "photo.artframe", title: "Wallpaper")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    NavigationLink {
                        ManageSubjectsView()
                    } label: {
                        settingsRow(icon: "book.fill", title: "Manage Subjects")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 28)
                        Toggle(isOn: $autoDimScreen) {
                            Text("Dim Screen While Recording")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                        }
                        .tint(PigeonTheme.accent)
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                } header: {
                    Text("Preferences")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 28)
                        
                        if isRequestingScope {
                            HStack {
                                Text("Google Photos Backup")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Spacer()
                                ProgressView()
                                    .tint(PigeonTheme.accent)
                            }
                        } else {
                            Toggle(isOn: $googlePhotosBackup) {
                                Text("Google Photos Backup")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                            }
                            .tint(PigeonTheme.accent)
                        }
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    .onChange(of: googlePhotosBackup) { _, enabled in
                        if enabled {
                            Task {
                                isRequestingScope = true
                                do {
                                    try await GooglePhotosService.shared.requestPhotosScope()
                                    GooglePhotosService.shared.isBackupEnabled = true
                                } catch {
                                    googlePhotosBackup = false
                                    GooglePhotosService.shared.isBackupEnabled = false
                                    scopeErrorMessage = error.localizedDescription
                                    showScopeError = true
                                }
                                isRequestingScope = false
                            }
                        } else {
                            GooglePhotosService.shared.isBackupEnabled = false
                        }
                    }
                } header: {
                    Text("Backup")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Section {
                    Button {
                        openURL(URL(string: "https://pigeonstudy.ing/support")!)
                    } label: {
                        settingsRow(icon: "questionmark.circle.fill", title: "Help & Support")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    Button {
                        openURL(URL(string: "https://pigeonstudy.ing/privacy")!)
                    } label: {
                        settingsRow(icon: "hand.raised.fill", title: "Privacy Policy")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                    NavigationLink {
                        SettingsPlaceholderView(title: "About Pigeon")
                    } label: {
                        settingsRow(icon: "info.circle.fill", title: "About Pigeon")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                } header: {
                    Text("Support")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Section {
                    Button {
                        Haptics.warning()
                        Task {
                            // Save current stats to Supabase before signing out
                            if let user = currentUser {
                                try? await SupabaseService.shared.saveUserProfile(user)
                            }
                            try? await AuthService.shared.signOut()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(PigeonTheme.destructive)
                            Text("Sign Out")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.destructive)
                        }
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PigeonTheme.background)
            .alert("Google Photos", isPresented: $showScopeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(scopeErrorMessage)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark))
    }
    
    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PigeonTheme.secondaryText)
                .frame(width: 28)
            Text(title)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.primaryText)
        }
    }
}

// MARK: - All Sessions View

struct AllSessionsView: View {
    let timelapses: [StudyTimelapse]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(timelapses) { timelapse in
                        TimelapseCardView(timelapse: timelapse)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(PigeonTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("All Sessions")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
    }
}

// MARK: - Settings Sub-Pages

struct SettingsPlaceholderView: View {
    let title: String
    
    private var icon: String {
        switch title {
        case "Notifications": return "bell.fill"
        case "Privacy": return "lock.shield.fill"
        case "Help & Support": return "envelope.fill"
        default: return "info.circle.fill"
        }
    }
    
    private var description: String {
        switch title {
        case "Notifications":
            return "Notification preferences will let you control study reminders, friend activity, and session alerts."
        case "Privacy":
            return "Privacy settings will let you manage who can see your study sessions and profile information."
        case "Help & Support":
            return "Have a question or found a bug? We'd love to hear from you."
        default:
            return "Pigeon helps you build consistent study habits through timelapses, tracking, and accountability."
        }
    }
    
    var body: some View {
        VStack(spacing: PigeonTheme.spacing24) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(PigeonTheme.secondaryText)
            
            VStack(spacing: PigeonTheme.spacing8) {
                Text(title)
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                
                Text(description)
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, PigeonTheme.spacing32)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PigeonTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
        }
        .toolbarBackground(PigeonTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [UserProfile.self, StudyTimelapse.self, StudySubject.self], inMemory: true)
}
