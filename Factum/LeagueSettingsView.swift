//
//  LeagueSettingsView.swift
//  Pigeon
//
//  Commissioner controls for a fantasy league
//

import SwiftUI

struct LeagueSettingsView: View {
    let league: FantasyLeagueRow
    var onUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var seasonEndDate: Date
    @State private var playoffTeams: Int
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    init(league: FantasyLeagueRow, onUpdated: @escaping () -> Void) {
        self.league = league
        self.onUpdated = onUpdated
        _name = State(initialValue: league.name)
        _description = State(initialValue: league.description)
        _seasonEndDate = State(initialValue: league.seasonEndDate)
        _playoffTeams = State(initialValue: league.playoffTeamCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEAGUE NAME")
                            .pigeonSectionTitle()
                        TextField("League Name", text: $name)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION")
                            .pigeonSectionTitle()
                        TextField("Description", text: $description)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("SEASON")
                            .pigeonSectionTitle()

                        HStack {
                            Text("Season End")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            DatePicker("", selection: $seasonEndDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                        HStack {
                            Text("Playoff Teams")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Stepper("\(playoffTeams)", value: $playoffTeams, in: 2...8)
                                .font(PigeonTheme.bodyFont)
                                .frame(width: 140)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    // League Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LEAGUE INFO")
                            .pigeonSectionTitle()
                        HStack {
                            Text("Members")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Text("\(league.memberUids.count)")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                        HStack {
                            Text("Roster Size")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Text("\(league.maxRosterSize) + \(league.benchSize) bench")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))

                        HStack {
                            Text("Draft Status")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Spacer()
                            Text(league.draftStatus.capitalized)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.secondaryText)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
                    }

                    // Save
                    Button {
                        Haptics.medium()
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Save Changes").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PigeonButtonStyle())
                    .disabled(isSaving)

                    // Delete League
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete League")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.destructive)
                    }
                    .padding(.top, 16)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(PigeonTheme.background)
            .navigationTitle("League Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PigeonTheme.bodyFont)
                }
            }
            .alert("Delete League?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task { await deleteLeague() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the league and all associated data. This cannot be undone.")
            }
        }
    }

    private func saveChanges() async {
        isSaving = true
        var updated = league
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.description = description
        updated.seasonEndDate = seasonEndDate
        updated.playoffTeamCount = playoffTeams
        do {
            try await SupabaseService.shared.updateFantasyLeague(updated)
            Haptics.success()
            onUpdated()
            dismiss()
        } catch {
            print("[LEAGUE] Settings save failed: \(error)")
            Haptics.error()
        }
        isSaving = false
    }

    private func deleteLeague() async {
        do {
            try await SupabaseService.shared.deleteFantasyLeague(id: league.id)
            Haptics.success()
            onUpdated()
            dismiss()
        } catch {
            print("[LEAGUE] Delete failed: \(error)")
            Haptics.error()
        }
    }
}
