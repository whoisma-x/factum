//
//  ProfileView.swift
//  Pigeon
//
//  User profile view with stats and Google sign-in
//

import SwiftUI
import SwiftData
import PhotosUI
import AuthenticationServices

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
    @State private var showAddQuota = false
    @State private var editingQuota: StudyQuota? = nil
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var userTimelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid }
    }
    
    @State private var profileTab = 0 // 0 = Progress, 1 = Sessions, 2 = Quotas
    private let profileTabs = [0, 1, 2]
    
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
                            label: { $0 == 0 ? "Progress" : $0 == 1 ? "Sessions" : "Quotas" }
                        )
                        .padding(.bottom, PigeonTheme.spacing16)
                        .staggeredAppear(index: 2, appeared: appeared)
                        
                        // Tab content
                        Group {
                            if profileTab == 0 {
                                progressTab(user: user)
                            } else if profileTab == 1 {
                                myPostsSection
                            } else {
                                quotasTab(user: user)
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
            .sheet(isPresented: $showAddQuota) {
                if let user = currentUser {
                    AddQuotaView(user: user, subjects: subjects)
                }
            }
            .sheet(item: $editingQuota) { quota in
                if let user = currentUser {
                    EditQuotaView(user: user, quota: quota, subjects: subjects)
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
    
    // MARK: - Quotas Tab

    private func quotasTab(user: UserProfile) -> some View {
        let quotas = user.studyQuotas

        return VStack(spacing: 12) {
            if quotas.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 40)
                    Image(systemName: "target")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Text("No study quotas yet")
                        .font(.gloucester(size: 14))
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Text("Set study targets for each subject\nto stay on track.")
                        .font(.gloucester(size: 11))
                        .foregroundStyle(PigeonTheme.secondaryText.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Spacer().frame(height: 20)
                }
            } else {
                ForEach(quotas) { quota in
                    let color = StudySubject.color(for: quota.subjectName, in: subjects)
                    Button {
                        Haptics.light()
                        editingQuota = quota
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color)
                                .frame(width: 10, height: 10)
                            Text(quota.subjectName)
                                .font(.gloucester(size: 13))
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Text(quotaFrequencyLabel(for: quota))
                                .font(.gloucester(size: 12))
                                .foregroundStyle(PigeonTheme.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(PigeonTheme.secondaryText.opacity(0.5))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .pigeonGlassSurface(cornerRadius: 12)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            var updated = user.studyQuotas
                            updated.removeAll { $0.id == quota.id }
                            user.studyQuotas = updated
                            try? modelContext.save()
                            Task {
                                await SupabaseService.shared.saveDailyQuotas(user.dailyQuotasJSON, forUser: user.firebaseUID ?? "")
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                Haptics.medium()
                showAddQuota = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Add Quota")
                        .font(.gloucester(size: 13))
                }
                .foregroundStyle(quotaGreen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(quotaGreen.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    /// Returns a human-readable label for a quota's frequency and target.
    private func quotaFrequencyLabel(for quota: StudyQuota) -> String {
        let time = formatQuotaTime(quota.targetMinutes)
        switch quota.frequency {
        case .daily:
            return "\(time)/day"
        case .weekly:
            return "\(time)/week"
        case .monthly:
            return "\(time)/month"
        case .yearly:
            return "\(time)/year"
        case .scheduled:
            if let days = quota.scheduledDays, !days.isEmpty {
                let dayNames = days.sorted(by: { $0.rawValue < $1.rawValue }).map(\.shortName).joined(separator: ", ")
                return "\(time) on \(dayNames)"
            }
            return "\(time)/scheduled"
        case .oneTime:
            if let deadline = quota.deadline {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMM d, yyyy"
                return "\(time) by \(fmt.string(from: deadline))"
            }
            return "\(time) total"
        }
    }

    // MARK: - Progress Tab (Strava-style)
    
    private func progressTab(user: UserProfile) -> some View {
        let totalHours = computedTotalStudyMinutes / 60
        let totalMins = computedTotalStudyMinutes % 60
        let longestMinutes = (userTimelapses.max(by: { $0.durationSeconds < $1.durationSeconds })?.durationSeconds ?? 0) / 60
        let mostInADayMinutes = computedMostInADay / 60
        
        return VStack(spacing: 20) {
            // Stats row (Strava-style: large values, small labels, dividers)
            HStack(spacing: 0) {
                PigeonStatCell(value: "\(totalHours)h \(totalMins)m", label: "Total Time")
                    .frame(maxWidth: .infinity)
                Rectangle().fill(PigeonTheme.separator).frame(width: 1, height: 32)
                PigeonStatCell(value: "\(userTimelapses.count)", label: "Sessions")
                    .frame(maxWidth: .infinity)
                Rectangle().fill(PigeonTheme.separator).frame(width: 1, height: 32)
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text("\(computedStreakDays)")
                            .font(.gloucester(size: 22))
                            .foregroundStyle(PigeonTheme.primaryText)
                        if computedStreakDays > 0 {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("Streak")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .pigeonGlassSurface(cornerRadius: PigeonTheme.cornerCard)
            
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
            
            // Sign in with Apple button (Guideline 4.8 compliant)
            SignInWithAppleButtonView(isSignUp: false)
                .padding(.horizontal, 20)
        }
    }
}
// (rest of the file unchanged)
