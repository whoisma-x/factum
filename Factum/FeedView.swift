//
//  FeedView.swift
//  Factum
//
//  Home feed showing study timelapse posts
//

import SwiftUI
import SwiftData
import AVKit

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyTimelapse.createdAt, order: .reverse) private var allTimelapses: [StudyTimelapse]
    @Query private var users: [UserProfile]
    @State private var showingNewTimelapse = false
    
    private var timelapses: [StudyTimelapse] {
        let uid = AuthService.shared.currentUserID
        return allTimelapses.filter { $0.authorID == uid }
    }
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "good morning"
        case 12..<17: return "good afternoon"
        case 17..<22: return "good evening"
        default: return "burning the midnight oil"
        }
    }
    
    private var firstName: String {
        let name = currentUser?.displayName ?? "Student"
        return name.components(separatedBy: " ").first ?? name
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Logo header
                    HStack(spacing: 8) {
                        FactumIcon(size: 24, color: FactumTheme.primaryText)
                        Text("factum")
                            .font(FactumTheme.titleFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .tracking(2)
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    // Greeting
                    VStack(spacing: 4) {
                        Text("\(greeting), \(firstName).")
                            .font(FactumTheme.headlineFont)
                            .foregroundStyle(FactumTheme.primaryText)
                        
                        Text(timelapses.isEmpty ? "ready to get to work?" : "here's your recent sessions.")
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    LazyVStack(spacing: 16) {
                        if timelapses.isEmpty {
                            emptyState
                        } else {
                            ForEach(timelapses) { timelapse in
                                TimelapseCardView(timelapse: timelapse)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(FactumTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingNewTimelapse) {
                TimelapseCameraView()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)
            
            FactumIcon(size: 56, color: FactumTheme.tertiaryText)
                .padding(.bottom, FactumTheme.spacing16)
            
            Text("Your feed is empty")
                .font(FactumTheme.font(18, weight: .regular))
                .foregroundStyle(FactumTheme.primaryText)
                .padding(.bottom, FactumTheme.spacing4)
            
            Text("Record a study session and it\nwill show up here.")
                .font(FactumTheme.captionFont)
                .foregroundStyle(FactumTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.bottom, FactumTheme.spacing24)
            
            Button("Record a Session") {
                showingNewTimelapse = true
            }
            .buttonStyle(FactumButtonStyle())
        }
    }
}

// MARK: - Timelapse Card

struct TimelapseCardView: View {
    let timelapse: StudyTimelapse
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
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
    
    private var isOwnPost: Bool {
        timelapse.authorID == AuthService.shared.currentUserID
    }
    
    private var hasMedia: Bool {
        timelapse.videoFileName != nil || timelapse.thumbnailData != nil
    }
    
    /// Card height adapts to content: portrait ~4:5, landscape ~16:9, no-media ~2:1
    private var videoAspectRatio: CGFloat {
        if !hasMedia { return 2.0 }
        return timelapse.isLandscape ? 16.0 / 9.0 : 4.0 / 5.0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timelapse auto-play video — tap to open detail
            GeometryReader { geo in
                let width = geo.size.width
                let height = width / videoAspectRatio
                
                ZStack(alignment: .topLeading) {
                        // Video / thumbnail fills the entire area — centered
                        // so any crop is split equally between top and bottom
                        if let cardPlayer {
                            FillVideoPlayerView(player: cardPlayer)
                                .frame(width: width, height: height)
                                .allowsHitTesting(false)
                        } else if let uiImage = cachedThumbnail {
                            if let afterImage = cachedAfterPhoto {
                                // Before/after carousel
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
                        } else {
                            // No-media post — show session stats centered
                            ZStack {
                                Rectangle()
                                    .fill(FactumTheme.surfaceBackground)
                                
                                HStack(spacing: 24) {
                                    // Duration
                                    VStack(spacing: 6) {
                                        Image(systemName: "clock.fill")
                                            .font(.system(size: 20))
                                            .frame(height: 22)
                                            .foregroundStyle(FactumTheme.accent)
                                        Text(timelapse.formattedDuration)
                                            .font(FactumTheme.font(16, weight: .bold))
                                            .frame(height: 20)
                                            .foregroundStyle(FactumTheme.primaryText)
                                        Text("Duration")
                                            .font(FactumTheme.smallFont)
                                            .frame(height: 14)
                                            .foregroundStyle(FactumTheme.tertiaryText)
                                    }
                                    
                                    Rectangle()
                                        .fill(FactumTheme.separator)
                                        .frame(width: 1, height: 44)
                                    
                                    // Subject
                                    VStack(spacing: 6) {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 20))
                                            .frame(height: 22)
                                            .foregroundStyle(StudySubject.color(for: timelapse.subject, in: subjects))
                                        Text(timelapse.subject)
                                            .font(FactumTheme.font(16, weight: .bold))
                                            .frame(height: 20)
                                            .foregroundStyle(FactumTheme.primaryText)
                                            .lineLimit(1)
                                        Text("Subject")
                                            .font(FactumTheme.smallFont)
                                            .frame(height: 14)
                                            .foregroundStyle(FactumTheme.tertiaryText)
                                    }
                                    
                                    if timelapse.appLeaveCount > 0 {
                                        Rectangle()
                                            .fill(FactumTheme.separator)
                                            .frame(width: 1, height: 44)
                                        
                                        // App leaves
                                        VStack(spacing: 6) {
                                            Image(systemName: "iphone.and.arrow.forward")
                                                .font(.system(size: 20))
                                                .frame(height: 22)
                                                .foregroundStyle(.red.opacity(0.7))
                                            Text("\(timelapse.appLeaveCount)")
                                                .font(FactumTheme.font(16, weight: .bold))
                                                .frame(height: 20)
                                                .foregroundStyle(FactumTheme.primaryText)
                                            Text("Left App")
                                                .font(FactumTheme.smallFont)
                                                .frame(height: 14)
                                                .foregroundStyle(FactumTheme.tertiaryText)
                                        }
                                    }
                                }
                                .padding(.top, 16)
                            }
                            .frame(width: width, height: height)
                        }
                        
                        // Overlay: Author header on top
                        HStack(spacing: 10) {
                            avatarView(name: timelapse.authorName, size: 36, avatarURL: timelapse.authorAvatarURL)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timelapse.authorName)
                                    .font(FactumTheme.subheadlineFont)
                                    .foregroundStyle(.white)
                                
                                Text(timelapse.createdAt.timeAgoDisplay())
                                    .font(FactumTheme.captionFont)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            // Subject tag — tappable if multi-subject
                            if timelapse.hasMultipleSubjects {
                                Button {
                                    Haptics.light()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showSubjectBreakdown.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(timelapse.subject)
                                            .font(FactumTheme.smallFont)
                                        Image(systemName: showSubjectBreakdown ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(StudySubject.color(for: timelapse.subject, in: subjects))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            } else {
                                Text(timelapse.subject)
                                    .font(FactumTheme.smallFont)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(StudySubject.color(for: timelapse.subject, in: subjects))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            if isOwnPost {
                                Menu {
                                    Button(role: .destructive) {
                                        Haptics.warning()
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            LinearGradient(
                                colors: [.black.opacity(0.5), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80)
                            .allowsHitTesting(false),
                            alignment: .top
                        )
                        
                        // Multi-subject breakdown dropdown
                        if showSubjectBreakdown {
                            VStack(alignment: .trailing, spacing: 0) {
                                HStack { Spacer() }
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(timelapse.subjectSegments) { segment in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(StudySubject.color(for: segment.subject, in: subjects))
                                                .frame(width: 8, height: 8)
                                            Text(segment.subject)
                                                .font(FactumTheme.smallFont)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text(formatSegmentDuration(segment.seconds))
                                                .font(FactumTheme.smallFont)
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                    }
                                }
                                .padding(10)
                                .background(.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .frame(maxWidth: 180)
                            }
                            .padding(.trailing, 12)
                            .padding(.top, 44)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Overlay: Duration badge on bottom-right
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(timelapse.formattedDuration)
                                    .font(FactumTheme.smallFont)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .padding(8)
                            }
                        }
                    }
                    .frame(width: width, height: height)
                    .clipped()
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
            
            // Caption and description
            VStack(alignment: .leading, spacing: 4) {
                Text(timelapse.caption)
                    .font(FactumTheme.font(16, weight: .regular))
                    .foregroundStyle(FactumTheme.primaryText)
                
                if !timelapse.studyDescription.isEmpty {
                    Text(timelapse.studyDescription)
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.tertiaryText)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, FactumTheme.spacing12)
            .padding(.top, 10)
            
            // Action bar — lighter weight, secondary
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
                    // MVP: Likes stay local only
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? FactumTheme.destructive : FactumTheme.secondaryText)
                        Text("\(timelapse.likeCount)")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }
                
                Button {
                    Haptics.light()
                    showDetail = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .foregroundStyle(FactumTheme.secondaryText)
                        Text("\(timelapse.commentCount)")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }

                Button {
                    Haptics.light()
                    guard InstagramStoriesSharer.isInstagramInstalled else {
                        showInstagramNotInstalled = true
                        return
                    }
                    showStoryStyleSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                
                Spacer()
            }
            .padding(.horizontal, FactumTheme.spacing12)
            .padding(.vertical, FactumTheme.spacing12)
        }
        .background(FactumTheme.cardBackground)
        .clipShape(OrganicRect(base: FactumTheme.cornerCard))
        .shadow(color: FactumTheme.cardShadow, radius: FactumTheme.cardShadowRadius, x: 0, y: FactumTheme.cardShadowY)
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
            Text("This will permanently delete this study session and its comments. This cannot be undone.")
        }
        .alert("Instagram Not Installed", isPresented: $showInstagramNotInstalled) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install Instagram to share your study sessions as stories.")
        }
        .fullScreenCover(isPresented: $showStoryStyleSheet) {
            let color = StudySubject.color(for: timelapse.subject, in: subjects)
            let colorResolver: (String) -> Color = { name in
                StudySubject.color(for: name, in: subjects)
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
                onExport: {}
            )
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
        
        // Delete local comments for this timelapse
        let descriptor = FetchDescriptor<TimelapseComment>(
            predicate: #Predicate { $0.timelapseID == timelapseID }
        )
        if let comments = try? modelContext.fetch(descriptor) {
            for comment in comments {
                modelContext.delete(comment)
            }
        }
        
        // Delete from SwiftData and persist immediately
        modelContext.delete(timelapse)
        try? modelContext.save()
        
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
    @Query private var comments: [TimelapseComment]
    @Query private var users: [UserProfile]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var newComment = ""
    @State private var player: AVPlayer?
    @State private var isLiked = false
    @State private var cachedThumbnail: UIImage?
    @State private var cachedAfterPhoto: UIImage?
    @State private var showInstagramNotInstalled = false
    @State private var showStoryStyleSheet = false
    
    private var currentUserName: String {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }?.displayName ?? "You"
    }
    
    private var filteredComments: [TimelapseComment] {
        comments.filter { $0.timelapseID == timelapse.id }
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
                                .fill(FactumTheme.surfaceBackground)
                                .overlay(
                                    HStack(spacing: 24) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 20))
                                                .frame(height: 22)
                                                .foregroundStyle(FactumTheme.accent)
                                            Text(timelapse.formattedDuration)
                                                .font(FactumTheme.font(16, weight: .bold))
                                                .frame(height: 20)
                                                .foregroundStyle(FactumTheme.primaryText)
                                            Text("Duration")
                                                .font(FactumTheme.smallFont)
                                                .frame(height: 14)
                                                .foregroundStyle(FactumTheme.tertiaryText)
                                        }
                                        
                                        Rectangle()
                                            .fill(FactumTheme.separator)
                                            .frame(width: 1, height: 44)
                                        
                                        VStack(spacing: 6) {
                                            Image(systemName: "book.fill")
                                                .font(.system(size: 20))
                                                .frame(height: 22)
                                                .foregroundStyle(StudySubject.color(for: timelapse.subject, in: subjects))
                                            Text(timelapse.subject)
                                                .font(FactumTheme.font(16, weight: .bold))
                                                .frame(height: 20)
                                                .foregroundStyle(FactumTheme.primaryText)
                                                .lineLimit(1)
                                            Text("Subject")
                                                .font(FactumTheme.smallFont)
                                                .frame(height: 14)
                                                .foregroundStyle(FactumTheme.tertiaryText)
                                        }
                                        
                                        if timelapse.appLeaveCount > 0 {
                                            Rectangle()
                                                .fill(FactumTheme.separator)
                                                .frame(width: 1, height: 44)
                                            
                                            VStack(spacing: 6) {
                                                Image(systemName: "iphone.and.arrow.forward")
                                                    .font(.system(size: 20))
                                                    .frame(height: 22)
                                                    .foregroundStyle(.red.opacity(0.7))
                                                Text("\(timelapse.appLeaveCount)")
                                                    .font(FactumTheme.font(16, weight: .bold))
                                                    .frame(height: 20)
                                                    .foregroundStyle(FactumTheme.primaryText)
                                                Text("Left App")
                                                    .font(FactumTheme.smallFont)
                                                    .frame(height: 14)
                                                    .foregroundStyle(FactumTheme.tertiaryText)
                                            }
                                        }
                                    }
                                    .padding(.top, 16)
                                )
                        }
                    }
                    .aspectRatio({
                        let hasMedia = timelapse.videoFileName != nil || timelapse.thumbnailData != nil
                        if !hasMedia { return 2.0 }
                        return timelapse.isLandscape ? 16.0 / 9.0 : 9.0 / 16.0
                    }(), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Author info
                    HStack(spacing: 12) {
                        avatarView(name: timelapse.authorName, size: 44, avatarURL: timelapse.authorAvatarURL)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timelapse.authorName)
                                .font(FactumTheme.subheadlineFont)
                                .foregroundStyle(FactumTheme.primaryText)
                            Text(timelapse.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(FactumTheme.captionFont)
                                .foregroundStyle(FactumTheme.tertiaryText)
                        }
                    }
                    
                    // Caption
                    Text(timelapse.caption)
                        .font(FactumTheme.headlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    // Subject(s)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "book.fill")
                                .foregroundStyle(FactumTheme.secondaryText)
                            Text(timelapse.subject)
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.secondaryText)
                        }
                        if timelapse.hasMultipleSubjects {
                            ForEach(timelapse.subjectSegments) { segment in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(StudySubject.color(for: segment.subject, in: subjects))
                                        .frame(width: 8, height: 8)
                                    Text(segment.subject)
                                        .font(FactumTheme.captionFont)
                                        .foregroundStyle(FactumTheme.primaryText)
                                    Spacer()
                                    Text(formatSegmentDuration(segment.seconds))
                                        .font(FactumTheme.captionFont)
                                        .foregroundStyle(FactumTheme.secondaryText)
                                }
                                .padding(.leading, 24)
                            }
                        }
                    }
                    
                    // Description
                    if !timelapse.studyDescription.isEmpty {
                        Text(timelapse.studyDescription)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                            .lineSpacing(4)
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
                            // MVP: Likes stay local only
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isLiked ? FactumTheme.destructive : FactumTheme.secondaryText)
                                Text("\(timelapse.likeCount)")
                                    .font(FactumTheme.bodyFont)
                                    .foregroundStyle(FactumTheme.secondaryText)
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 18))
                                .foregroundStyle(FactumTheme.secondaryText)
                            Text("\(timelapse.commentCount)")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.secondaryText)
                        }
                        
                        Spacer()
                        
                        Button {
                            Haptics.light()
                            guard InstagramStoriesSharer.isInstagramInstalled else {
                                showInstagramNotInstalled = true
                                return
                            }
                            showStoryStyleSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(FactumTheme.secondaryText)
                        }
                    }
                    
                    Divider()
                        .background(FactumTheme.separator)
                    
                    // Comments section
                    Text("Comments")
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    if filteredComments.isEmpty {
                        Text("No comments yet. Be the first!")
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.tertiaryText)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredComments) { comment in
                            CommentRow(comment: comment)
                        }
                    }
                    
                    // Add comment
                    HStack(spacing: 10) {
                        TextField("Add a comment...", text: $newComment)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .padding(12)
                            .background(FactumTheme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        Button {
                            Haptics.light()
                            guard !newComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let comment = TimelapseComment(
                                timelapseID: timelapse.id,
                                authorID: AuthService.shared.currentUserID,
                                authorName: currentUserName,
                                text: newComment
                            )
                            modelContext.insert(comment)
                            timelapse.commentCount += 1
                            // MVP: Comments stay local only
                            newComment = ""
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(FactumTheme.accent)
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FactumTheme.background)
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
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Instagram Not Found", isPresented: $showInstagramNotInstalled) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Install Instagram to share your study stats to your Story.")
            }
            .fullScreenCover(isPresented: $showStoryStyleSheet) {
                let color = StudySubject.color(for: timelapse.subject, in: subjects)
                let colorResolver: (String) -> Color = { name in
                    StudySubject.color(for: name, in: subjects)
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
                    onExport: {}
                )
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
        .presentationBackground(FactumTheme.background)
    }
}

struct CommentRow: View {
    let comment: TimelapseComment
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView(name: comment.authorName, size: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.authorName)
                        .font(FactumTheme.font(13, weight: .semibold))
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    Text(comment.createdAt.timeAgoDisplay())
                        .font(FactumTheme.smallFont)
                        .foregroundStyle(FactumTheme.tertiaryText)
                }
                
                Text(comment.text)
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
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
                        .fill(FactumTheme.elevated)
                        .frame(width: size, height: size)
                        .overlay(
                            Text(initial)
                                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                                .foregroundStyle(FactumTheme.primaryText)
                        )
                }
            }
        } else {
            Circle()
                .fill(FactumTheme.elevated)
                .frame(width: size, height: size)
                .overlay(
                    Text(initial)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(FactumTheme.primaryText)
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
