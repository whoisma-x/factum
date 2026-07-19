//
//  ManageSubjectsView.swift
//  Factum
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
                    }
                    
                    Button {
                        showAddSubject = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(FactumTheme.accent)
                            Text("Add Subject")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.accent)
                        }
                    }
                } header: {
                    Text("Subjects")
                        .font(FactumTheme.smallFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FactumTheme.background)
            .navigationTitle("Manage Subjects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
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
        .presentationBackground(FactumTheme.background)
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
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            Spacer()
        }
        .listRowBackground(FactumTheme.cardBackground)
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
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    TextField("e.g. Economics", text: $name)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                        .padding(14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Color selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(presetColors, id: \.0) { colorName, color in
                            Button {
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
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
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
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(name.isEmpty ? FactumTheme.tertiaryText : FactumTheme.primaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FactumTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Save button
                Button {
                    subject.name = name.trimmingCharacters(in: .whitespaces)
                    subject.colorHex = selectedColor.hexString
                    try? modelContext.save()
                    syncSubjectsToCloud()
                    dismiss()
                } label: {
                    Text("Save Changes")
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? FactumTheme.elevated
                            : FactumTheme.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(FactumTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationTitle("Edit Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                name = subject.name
                selectedColor = subject.color
            }
        }
        .presentationBackground(FactumTheme.background)
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
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    TextField("e.g. Economics", text: $name)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                        .padding(14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Color selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(presetColors, id: \.0) { colorName, color in
                            Button {
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
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
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
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(name.isEmpty ? FactumTheme.tertiaryText : FactumTheme.primaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FactumTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Save button
                Button {
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
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? FactumTheme.elevated
                            : FactumTheme.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(FactumTheme.background)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .navigationTitle("New Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(FactumTheme.accent)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(FactumTheme.background)
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
