//
//  ManageSubjectsView.swift
//  Pigeon
//
//  CRUD interface for managing study subjects and their colors
//

import SwiftUI
import SwiftData

struct ManageSubjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var showAddSubject = false
    @State private var subjectToEdit: StudySubject?
    
    private var sortedSubjects: [StudySubject] {
        subjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedSubjects) { subject in
                        subjectRow(subject)
                            .contextMenu {
                                Button {
                                    subjectToEdit = subject
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteSubject(subject)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteSubject(subject)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    subjectToEdit = subject
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(PigeonTheme.accent)
                            }
                    }
                    
                    Button {
                        Haptics.light()
                        showAddSubject = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(PigeonTheme.accent)
                            Text("Add Subject")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.accent)
                        }
                    }
                } header: {
                    Text("Subjects")
                        .font(PigeonTheme.smallFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PigeonTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Manage Subjects")
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
            .sheet(isPresented: $showAddSubject) {
                AddSubjectView()
            }
            .sheet(item: $subjectToEdit) { subject in
                EditSubjectView(subject: subject)
            }
            .task {
                deduplicateSubjects()
            }
        }
        .presentationBackground(PigeonTheme.background)
    }
    
    private func deleteSubject(_ subject: StudySubject) {
        modelContext.delete(subject)
        try? modelContext.save()
        syncSubjectsToCloud()
    }
    
    private func deduplicateSubjects() {
        var seen = [String: StudySubject]()
        var removed = 0
        for subject in subjects {
            let key = subject.name.lowercased()
            if seen[key] != nil {
                modelContext.delete(subject)
                removed += 1
            } else {
                seen[key] = subject
            }
        }
        if removed > 0 {
            try? modelContext.save()
            print("[SUBJECTS] Removed \(removed) local duplicate subjects")
            syncSubjectsToCloud()
        }
    }
    
    private func syncSubjectsToCloud() {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        let allSubjects = subjects
        Task {
            try? await SupabaseService.shared.saveSubjects(allSubjects, forUser: uid)
            print("[SYNC] Subjects synced to Supabase (\(allSubjects.count) subjects)")
        }
    }
    
    private func subjectRow(_ subject: StudySubject) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(subject.color)
                .frame(width: 14, height: 14)
            
            Text(subject.name)
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.primaryText)
            
            Spacer()
        }
        .listRowBackground(PigeonTheme.cardBackground)
    }
}

// MARK: - Edit Subject View

struct EditSubjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    let subject: StudySubject
    @State private var name: String = ""
    @State private var selectedColor: Color = .blue
    
    private let presetColors: [(String, Color)] = [
        ("Blue", Color(hex: "#3478F6")!),
        ("Red", Color(hex: "#FF3B30")!),
        ("Green", Color(hex: "#34C759")!),
        ("Orange", Color(hex: "#FF9500")!),
        ("Purple", Color(hex: "#AF52DE")!),
        ("Teal", Color(hex: "#5AC8FA")!),
        ("Pink", Color(hex: "#FF2D55")!),
        ("Yellow", Color(hex: "#FFCC00")!),
        ("Indigo", Color(hex: "#5856D6")!),
        ("Mint", Color(hex: "#00C7BE")!),
        ("Brown", Color(hex: "#A2845E")!),
        ("Cyan", Color(hex: "#32ADE6")!),
    ]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subject Name")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    TextField("e.g. Economics", text: $name)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Color selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(presetColors, id: \.0) { colorName, color in
                            Button {
                                Haptics.selection()
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                            }
                        }
                    }
                    
                    // Custom color picker
                    HStack(spacing: 12) {
                        Text("Custom")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                
                // Preview
                HStack(spacing: 10) {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 14, height: 14)
                    Text(name.isEmpty ? "Preview" : name)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(name.isEmpty ? PigeonTheme.tertiaryText : PigeonTheme.primaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Save button
                Button {
                    Haptics.medium()
                    let newName = name.trimmingCharacters(in: .whitespaces)
                    let oldName = subject.name
                    
                    // Update the subject itself
                    subject.name = newName
                    subject.colorHex = selectedColor.hexString
                    
                    // Cascade rename to all timelapse records that reference the old name
                    if oldName != newName {
                        let descriptor = FetchDescriptor<StudyTimelapse>()
                        if let allTimelapses = try? modelContext.fetch(descriptor) {
                            for timelapse in allTimelapses {
                                // Update legacy subject field
                                if timelapse.subject == oldName {
                                    timelapse.subject = newName
                                }
                                // Update subject segments JSON
                                var segments = timelapse.subjectSegments
                                var changed = false
                                for i in segments.indices where segments[i].subject == oldName {
                                    segments[i] = SubjectSegment(subject: newName, seconds: segments[i].seconds)
                                    changed = true
                                }
                                if changed {
                                    timelapse.subjectSegments = segments
                                }
                            }
                        }
                    }
                    
                    try? modelContext.save()
                    syncSubjectsToCloud()
                    dismiss()
                } label: {
                    Text("Save Changes")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? PigeonTheme.elevated
                            : PigeonTheme.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(PigeonTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Subject")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                name = subject.name
                selectedColor = subject.color
            }
        }
        .presentationBackground(PigeonTheme.background)
    }
    
    private func syncSubjectsToCloud() {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        let allSubjects = subjects
        Task {
            try? await SupabaseService.shared.saveSubjects(allSubjects, forUser: uid)
        }
    }
}

// MARK: - Add Subject View

struct AddSubjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var name = ""
    @State private var selectedColor = Color.blue
    
    private let presetColors: [(String, Color)] = [
        ("Blue", Color(hex: "#3478F6")!),
        ("Red", Color(hex: "#FF3B30")!),
        ("Green", Color(hex: "#34C759")!),
        ("Orange", Color(hex: "#FF9500")!),
        ("Purple", Color(hex: "#AF52DE")!),
        ("Teal", Color(hex: "#5AC8FA")!),
        ("Pink", Color(hex: "#FF2D55")!),
        ("Yellow", Color(hex: "#FFCC00")!),
        ("Indigo", Color(hex: "#5856D6")!),
        ("Mint", Color(hex: "#00C7BE")!),
        ("Brown", Color(hex: "#A2845E")!),
        ("Cyan", Color(hex: "#32ADE6")!),
    ]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subject Name")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    TextField("e.g. Economics", text: $name)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Color selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(presetColors, id: \.0) { colorName, color in
                            Button {
                                Haptics.selection()
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                            }
                        }
                    }
                    
                    // Custom color picker
                    HStack(spacing: 12) {
                        Text("Custom")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                
                // Preview
                HStack(spacing: 10) {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 14, height: 14)
                    Text(name.isEmpty ? "Preview" : name)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(name.isEmpty ? PigeonTheme.tertiaryText : PigeonTheme.primaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Save button
                Button {
                    Haptics.medium()
                    let nextOrder = (subjects.last?.sortOrder ?? 0) + 1
                    let subject = StudySubject(
                        name: name,
                        colorHex: selectedColor.hexString,
                        isUserCreated: true,
                        sortOrder: nextOrder
                    )
                    modelContext.insert(subject)
                    try? modelContext.save()
                    syncSubjectsToCloud()
                    dismiss()
                } label: {
                    Text("Add Subject")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? PigeonTheme.elevated
                            : PigeonTheme.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(PigeonTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Subject")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.accent)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
    }
    
    private func syncSubjectsToCloud() {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        let allSubjects = subjects
        Task {
            try? await SupabaseService.shared.saveSubjects(allSubjects, forUser: uid)
        }
    }
}
