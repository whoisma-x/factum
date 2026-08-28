//
//  PostCaptionView.swift
//  Pigeon
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
    var capturedPhotos: [UIImage] = []
    var subjectSegments: [SubjectSegment] = []
    var appLeaveCount: Int = 0
    var offTaskSeconds: Int = 0
    let onComplete: () -> Void
    var onDiscard: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var caption = ""
    @State private var studyDescription = ""
    @State private var isPosting = false
    @State private var isCheckingContent = false
    @State private var showContentWarning = false
    @State private var contentWarningMessage = ""
    @State private var currentPhotoIndex = 0
    @State private var showDiscardConfirm = false
    @State private var showExportOverlay = false
    @State private var showVideoEditor = false
    @State private var editedVideoURL: URL? = nil
    @FocusState private var focusedField: Field?
    @Query private var users: [UserProfile]
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    
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
    
    /// Video URL — uses edited version if available, otherwise original
    private var effectiveVideoURL: URL? {
        editedVideoURL ?? videoURL
    }
    
    /// Primary subject — the one with the most time from segments
    private var primarySubjectName: String {
        subjectSegments.first?.subject ?? "General"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Session summary
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(PigeonTheme.surfaceBackground)
                                .frame(width: 100, height: 75)
                            
                            VStack(spacing: 4) {
                                Image(systemName: videoURL != nil ? "timelapse" : (!capturedPhotos.isEmpty ? "camera.fill" : "timer"))
                                    .font(.system(size: 24))
                                    .foregroundStyle(PigeonTheme.secondaryText)
                                Text(formatDuration(durationSeconds))
                                    .font(PigeonTheme.font(12, weight: .semibold))
                                    .foregroundStyle(PigeonTheme.primaryText)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Study Session Complete")
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Text("Add details about your session")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Photo preview carousel
                    if !capturedPhotos.isEmpty {
                        VStack(spacing: 8) {
                            TabView(selection: $currentPhotoIndex) {
                                ForEach(capturedPhotos.indices, id: \.self) { index in
                                    Image(uiImage: capturedPhotos[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxHeight: 300)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: capturedPhotos.count > 1 ? .always : .never))
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            if capturedPhotos.count > 1 {
                                HStack(spacing: 16) {
                                    Text("Before")
                                        .font(PigeonTheme.font(12, weight: currentPhotoIndex == 0 ? .bold : .medium))
                                        .foregroundStyle(currentPhotoIndex == 0 ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                    Text("After")
                                        .font(PigeonTheme.font(12, weight: currentPhotoIndex == 1 ? .bold : .medium))
                                        .foregroundStyle(currentPhotoIndex == 1 ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                }
                            }
                        }
                    }
                    
                    // Edit Video button
                    if let url = effectiveVideoURL, UIVideoEditorController.canEditVideo(atPath: url.path) {
                        Button {
                            Haptics.light()
                            showVideoEditor = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scissors")
                                    .font(.system(size: 16))
                                Text("Edit Video")
                                    .font(PigeonTheme.subheadlineFont)
                            }
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(PigeonTheme.separator, lineWidth: 1)
                            )
                        }
                    }

                    // Caption
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Caption")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        
                        TextField("e.g. late night grind session", text: $caption)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .focused($focusedField, equals: .caption)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $studyDescription)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                                .focused($focusedField, equals: .description)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(PigeonTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            if studyDescription.isEmpty {
                                Text("what did you study? any breakthroughs?")
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
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
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.accentText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                (caption.isEmpty || isPosting || isCheckingContent)
                                ? PigeonTheme.elevated
                                : PigeonTheme.accent
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(caption.isEmpty || isPosting || isCheckingContent)
                    .padding(.top, 8)

                    // Export & Share — unified export screen
                    Button {
                        Haptics.light()
                        showExportOverlay = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                            Text("Export & Share")
                                .font(PigeonTheme.subheadlineFont)
                        }
                        .foregroundStyle(PigeonTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(PigeonTheme.separator, lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .background(PigeonTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Post")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    // Go back to the paused timer/timelapse
                    Button("Back") {
                        if let onDiscard {
                            onDiscard()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(PigeonTheme.secondaryText)
                    .font(PigeonTheme.bodyFont)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Exit to main feed without posting
                    Button {
                        Haptics.warning()
                        showDiscardConfirm = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(PigeonTheme.secondaryText)
                    }
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Content Warning", isPresented: $showContentWarning) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(contentWarningMessage)
            }
            .alert("Skip posting?", isPresented: $showDiscardConfirm) {
                Button("Save without posting", role: .destructive) {
                    // Save the session record locally and sync to cloud even if the
                    // user doesn't want to write a caption. Study time is never lost.
                    Task { await saveAndDismiss() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your study time will still be saved to your history.")
            }
            .fullScreenCover(isPresented: $showExportOverlay) {
                let color = StudySubject.color(for: primarySubjectName, in: subjects)
                let colorResolver: (String) -> Color = { name in
                    StudySubject.color(for: name, in: subjects)
                }
                TimelapseExportView(
                    thumbnailData: thumbnailData,
                    videoURL: effectiveVideoURL,
                    durationSeconds: durationSeconds,
                    subjectName: primarySubjectName,
                    subjectColor: color,
                    date: Date(),
                    caption: caption,
                    appLeaveCount: appLeaveCount,
                    subjectSegments: subjectSegments,
                    subjectColorResolver: colorResolver
                )
            }
            .fullScreenCover(isPresented: $showVideoEditor) {
                if let url = effectiveVideoURL {
                    VideoEditorView(videoURL: url) { editedURL in
                        self.editedVideoURL = editedURL
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .presentationBackground(PigeonTheme.background)
    }
    
    /// Save the session to history without requiring a caption, then dismiss.
    /// Ensures study time is never lost even if the user skips posting.
    @MainActor
    private func saveAndDismiss() async {
        let uid = AuthService.shared.currentUserID
        let effectiveThumbnail = thumbnailData ?? capturedPhotos.first?.jpegData(compressionQuality: 0.8)
        
        let timelapse = StudyTimelapse(
            authorID: uid,
            authorName: currentUserName,
            authorAvatarURL: currentUserAvatarURL,
            caption: "",
            studyDescription: "",
            subject: primarySubjectName,
            durationSeconds: durationSeconds,
            videoFileName: effectiveVideoURL?.lastPathComponent,
            thumbnailData: effectiveThumbnail,
            isLandscape: isLandscape
        )
        timelapse.appLeaveCount = appLeaveCount
        timelapse.offTaskSeconds = offTaskSeconds
        if subjectSegments.count > 1 {
            timelapse.subjectSegments = subjectSegments
        }
        modelContext.insert(timelapse)
        if let user = users.first(where: { $0.firebaseUID == uid }) {
            user.totalStudyMinutes += durationSeconds / 60
        }
        
        for attempt in 1...3 {
            do {
                try modelContext.save()
                break
            } catch {
                print("[SAVE] Save attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }
        
        // Sync to cloud
        SyncManager.shared.uploadSession(timelapse, videoURL: effectiveVideoURL, context: modelContext)
        
        onComplete()
    }
    
    @MainActor
    private func postTimelapse() async {
        // Content moderation check before posting
        isCheckingContent = true
        
        // Pre-encode photos once — reused for moderation, thumbnail, and storage
        let encodedPhotos: [Data] = capturedPhotos.compactMap {
            $0.jpegData(compressionQuality: 0.8)
        }
        
        // Check text content
        let textResult = await ContentModerationService.shared.checkText([caption, studyDescription])
        if case .flagged(let reason) = textResult {
            isCheckingContent = false
            contentWarningMessage = reason
            showContentWarning = true
            return
        }
        
        // Check all photos using pre-encoded data
        for data in encodedPhotos {
            let imageResult = await ContentModerationService.shared.checkImage(data)
            if case .flagged(let reason) = imageResult {
                isCheckingContent = false
                contentWarningMessage = reason
                showContentWarning = true
                return
            }
        }
        // Also check thumbnail if no captured photos
        if encodedPhotos.isEmpty, let thumbnailData {
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
        // Use the first pre-encoded photo as thumbnail if no explicit thumbnail
        let effectiveThumbnail = thumbnailData ?? encodedPhotos.first
        // Second photo (after) stored separately for before/after carousel
        let afterData = encodedPhotos.count > 1 ? encodedPhotos[1] : nil
        
        let timelapse = StudyTimelapse(
            authorID: uid,
            authorName: currentUserName,
            authorAvatarURL: currentUserAvatarURL,
            caption: caption,
            studyDescription: studyDescription,
            subject: primarySubjectName,
            durationSeconds: durationSeconds,
            videoFileName: effectiveVideoURL?.lastPathComponent,
            thumbnailData: effectiveThumbnail,
            isLandscape: isLandscape
        )
        timelapse.afterPhotoData = afterData
        timelapse.appLeaveCount = appLeaveCount
        timelapse.offTaskSeconds = offTaskSeconds
        if subjectSegments.count > 1 {
            timelapse.subjectSegments = subjectSegments
        }
        modelContext.insert(timelapse)
        // Update user stats locally
        if let user = users.first(where: { $0.firebaseUID == uid }) {
            user.totalStudyMinutes += durationSeconds / 60
        }
        
        // Save locally — retry up to 3 times to ensure the session is never lost
        for attempt in 1...3 {
            do {
                try modelContext.save()
                break
            } catch {
                print("[SAVE] Local save attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt == 3 {
                    print("[SAVE] WARNING: Local save failed after 3 attempts — session will be in-memory only until next save")
                }
            }
        }
        
        // Capture values needed for background tasks
        let capturedVideoURL = effectiveVideoURL
        let capturedSubjectName = primarySubjectName
        let capturedCaption = caption
        let capturedTimelapse = timelapse
        let ctx = modelContext
        
        // Upload session record + media to Supabase with automatic retries.
        // SyncManager handles exponential backoff and will retry on foreground
        // if the initial attempts fail, ensuring data is never lost.
        SyncManager.shared.uploadSession(
            capturedTimelapse,
            videoURL: capturedVideoURL,
            context: ctx
        )
        
        // Google Photos backup (optional, user-controlled — independent of Supabase)
        let isBackupEnabled = GooglePhotosService.shared.isBackupEnabled
        Task.detached {
            if isBackupEnabled, let videoURL = capturedVideoURL {
                do {
                    let fileName = videoURL.lastPathComponent
                    let desc = "Pigeon: \(capturedSubjectName) — \(capturedCaption)"
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

// MARK: - Video Editor (UIVideoEditorController wrapper)

struct VideoEditorView: UIViewControllerRepresentable {
    let videoURL: URL
    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIVideoEditorController {
        let editor = UIVideoEditorController()
        editor.videoPath = videoURL.path
        editor.videoQuality = .typeHigh
        editor.delegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ uiViewController: UIVideoEditorController, context: Context) {}

    class Coordinator: NSObject, UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
        let onSave: (URL) -> Void
        let dismiss: DismissAction

        init(onSave: @escaping (URL) -> Void, dismiss: DismissAction) {
            self.onSave = onSave
            self.dismiss = dismiss
        }

        func videoEditorController(_ editor: UIVideoEditorController, didSaveEditedVideoToPath editedVideoPath: String) {
            let editedURL = URL(fileURLWithPath: editedVideoPath)
            onSave(editedURL)
            dismiss()
        }

        func videoEditorControllerDidCancel(_ editor: UIVideoEditorController) {
            dismiss()
        }

        func videoEditorController(_ editor: UIVideoEditorController, didFailWithError error: any Error) {
            print("[VIDEO EDITOR] Failed: \(error.localizedDescription)")
            dismiss()
        }
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
