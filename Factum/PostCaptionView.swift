//
//  PostCaptionView.swift
//  Factum
//
//  Post-timelapse caption and description entry
//

import SwiftUI
import SwiftData
import Photos

struct PostCaptionView: View {
    let durationSeconds: Int
    var videoURL: URL? = nil
    var thumbnailData: Data? = nil
    var isLandscape: Bool = false
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var caption = ""
    @State private var studyDescription = ""
    @State private var selectedSubjectID: UUID? = nil
    @State private var showAddSubject = false
    @State private var isPosting = false
    @State private var isCheckingContent = false
    @State private var showContentWarning = false
    @State private var contentWarningMessage = ""
    @State private var savedToPhotos = false
    @State private var isSavingToPhotos = false
    @FocusState private var focusedField: Field?
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @Query private var users: [UserProfile]
    
    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    private var currentUserName: String {
        currentUser?.displayName ?? "You"
    }
    
    private var currentUserAvatarURL: String? {
        currentUser?.avatarURL
    }
    
    enum Field {
        case caption, description
    }
    
    private var selectedSubjectName: String {
        subjects.first { $0.id == selectedSubjectID }?.name ?? "General"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Session summary
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(FactumTheme.surfaceBackground)
                                .frame(width: 100, height: 75)
                            
                            VStack(spacing: 4) {
                                Image(systemName: "timelapse")
                                    .font(.system(size: 24))
                                    .foregroundStyle(FactumTheme.secondaryText)
                                Text(formatDuration(durationSeconds))
                                    .font(FactumTheme.font(12, weight: .semibold))
                                    .foregroundStyle(FactumTheme.primaryText)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Study Session Complete")
                                .font(FactumTheme.subheadlineFont)
                                .foregroundStyle(FactumTheme.primaryText)
                            Text("Add details about your session")
                                .font(FactumTheme.captionFont)
                                .foregroundStyle(FactumTheme.secondaryText)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FactumTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Caption
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Caption")
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(FactumTheme.primaryText)
                        
                        TextField("e.g. late night grind session", text: $caption)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .focused($focusedField, equals: .caption)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Subject picker (choose one)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subject")
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(FactumTheme.primaryText)
                        
                        // Scrollable subject tags — tap to select
                        FlowLayout(spacing: 8) {
                            ForEach(subjects) { studySubject in
                                Button {
                                    selectedSubjectID = studySubject.id
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(studySubject.color)
                                            .frame(width: 8, height: 8)
                                        Text(studySubject.name)
                                            .font(FactumTheme.captionFont)
                                    }
                                    .foregroundStyle(
                                        selectedSubjectID == studySubject.id
                                        ? Color.black
                                        : FactumTheme.secondaryText
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedSubjectID == studySubject.id
                                        ? studySubject.color
                                        : FactumTheme.elevated
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            
                            // Create new subject inline
                            Button {
                                showAddSubject = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("New")
                                        .font(FactumTheme.captionFont)
                                }
                                .foregroundStyle(FactumTheme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(FactumTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(FactumTheme.separator, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .sheet(isPresented: $showAddSubject) {
                        AddSubjectView()
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(FactumTheme.primaryText)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $studyDescription)
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.primaryText)
                                .focused($focusedField, equals: .description)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(FactumTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            if studyDescription.isEmpty {
                                Text("what did you study? any breakthroughs?")
                                    .font(FactumTheme.bodyFont)
                                    .foregroundStyle(FactumTheme.tertiaryText)
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    
                    // Post button
                    Button {
                        Task { await postTimelapse() }
                    } label: {
                        Text(isCheckingContent ? "Checking content..." : (isPosting ? "Saving..." : "Share Session"))
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(FactumTheme.accentText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                (caption.isEmpty || isPosting || isCheckingContent)
                                ? FactumTheme.elevated
                                : FactumTheme.accent
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(caption.isEmpty || isPosting || isCheckingContent)
                    .padding(.top, 8)

                    // Save to Camera Roll
                    if videoURL != nil {
                        Button {
                            Task { await saveToPhotos() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.system(size: 16))
                                Text(savedToPhotos ? "Saved to Camera Roll" : (isSavingToPhotos ? "Saving..." : "Save to Camera Roll"))
                                    .font(FactumTheme.subheadlineFont)
                            }
                            .foregroundStyle(savedToPhotos ? .green : FactumTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(FactumTheme.separator, lineWidth: 1)
                            )
                        }
                        .disabled(savedToPhotos || isSavingToPhotos)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .background(FactumTheme.background)
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                        .foregroundStyle(FactumTheme.destructive)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Content Warning", isPresented: $showContentWarning) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(contentWarningMessage)
            }
        }
        .presentationBackground(FactumTheme.background)
    }
    
    @MainActor
    private func postTimelapse() async {
        // Content moderation check before posting
        isCheckingContent = true
        
        // Check text content
        let textResult = await ContentModerationService.shared.checkText([caption, studyDescription])
        if case .flagged(let reason) = textResult {
            isCheckingContent = false
            contentWarningMessage = reason
            showContentWarning = true
            return
        }
        
        // Check thumbnail image if available
        if let thumbnailData {
            let imageResult = await ContentModerationService.shared.checkImage(thumbnailData)
            if case .flagged(let reason) = imageResult {
                isCheckingContent = false
                contentWarningMessage = reason
                showContentWarning = true
                return
            }
        }
        
        isCheckingContent = false
        
        let uid = AuthService.shared.currentUserID
        let timelapse = StudyTimelapse(
            authorID: uid,
            authorName: currentUserName,
            authorAvatarURL: currentUserAvatarURL,
            caption: caption,
            studyDescription: studyDescription,
            subject: selectedSubjectName,
            durationSeconds: durationSeconds,
            videoFileName: videoURL?.lastPathComponent,
            thumbnailData: thumbnailData,
            isLandscape: isLandscape
        )
        modelContext.insert(timelapse)
        // Update user stats locally
        if let user = users.first(where: { $0.firebaseUID == uid }) {
            user.totalStudyMinutes += durationSeconds / 60
        }
        
        // Save locally
        try? modelContext.save()
        
        // Capture values needed for background tasks
        let capturedVideoURL = videoURL
        let capturedSubjectName = selectedSubjectName
        let capturedCaption = caption
        let capturedTimelapse = timelapse
        let capturedUser = users.first(where: { $0.firebaseUID == uid })
        let ctx = modelContext
        
        // MVP: Cloud upload disabled — video and thumbnail stay local only.
        // Sync updated user stats to Supabase (totalStudyMinutes was just incremented)
        Task {
            if let user = capturedUser {
                try? await SupabaseService.shared.saveUserProfile(user)
            }
        }
        
        // Google Photos backup (optional, user-controlled — independent of Supabase)
        Task.detached {
            if GooglePhotosService.shared.isBackupEnabled, let videoURL = capturedVideoURL {
                do {
                    let fileName = videoURL.lastPathComponent
                    let desc = "Factum: \(capturedSubjectName) — \(capturedCaption)"
                    try await GooglePhotosService.shared.uploadVideo(
                        localURL: videoURL,
                        fileName: fileName,
                        description: desc
                    )
                    await MainActor.run {
                        capturedTimelapse.googlePhotosBackedUp = true
                        try? ctx.save()
                    }
                    print("[PHOTOS] Timelapse backed up successfully")
                } catch {
                    print("[PHOTOS] Backup failed: \(error.localizedDescription)")
                }
            }
        }
        
        onComplete()
    }
    
    @MainActor
    private func saveToPhotos() async {
        guard let videoURL else { return }
        isSavingToPhotos = true

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isSavingToPhotos = false
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }
            savedToPhotos = true
        } catch {
            print("[SAVE] Failed to save to Camera Roll: \(error.localizedDescription)")
        }
        isSavingToPhotos = false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%dh %dm %ds", h, m, s)
        } else if m > 0 {
            return String(format: "%dm %ds", m, s)
        }
        return String(format: "%ds", s)
    }
}

// MARK: - Flow Layout (wrapping tag layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }
        
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
