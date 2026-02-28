//
//  CreateTeamView.swift
//  MPS-iOS
//

import SwiftUI

struct CreateTeamView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var allUsers: [User] = []
    @State private var userTeamMap: [Int: String] = [:]
    @State private var selectedMemberIds: Set<Int> = []
    @State private var teamLeadId: Int? = nil
    @State private var isLoadingUsers = false
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

    private var selectedMembers: [User] {
        allUsers.filter { selectedMemberIds.contains($0.id) }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMembers = !selectedMemberIds.isEmpty
        let hasLead = teamLeadId != nil
        return hasName && hasMembers && hasLead
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                membersSection
                teamLeadSection
            }
            .navigationTitle("New Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
            .task { await load() }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Team Name", text: $name)
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        Section("Members") {
            if isLoadingUsers {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(allUsers, id: \.id) { user in
                    MemberRow(
                        user: user,
                        isSelected: selectedMemberIds.contains(user.id),
                        assignedTeamName: userTeamMap[user.id],
                        onTap: { toggleMember(user) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var teamLeadSection: some View {
        Section("Team Lead") {
            if selectedMemberIds.isEmpty {
                Text("Select members first")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Team Lead", selection: $teamLeadId) {
                    Text("Select…").tag(Optional<Int>.none)
                    ForEach(selectedMembers) { user in
                        Text(user.fullName).tag(Optional<Int>.some(user.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if isSaving {
            ProgressView()
        } else {
            Button("Add") { Task { await save() } }
                .disabled(!canSave)
        }
    }

    // MARK: - Helpers

    private func toggleMember(_ user: User) {
        if selectedMemberIds.contains(user.id) {
            selectedMemberIds.remove(user.id)
            if teamLeadId == user.id { teamLeadId = nil }
        } else {
            selectedMemberIds.insert(user.id)
        }
    }

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            struct LoadResponse: Decodable {
                let users: [User]
                let teams: [Team]
            }
            let result: LoadResponse = try await client.fetch(
                query: """
                {
                    users { id fullName craftAbility jobLevel craftFocus levelStartDate }
                    teams { id name teamLead { id fullName } members { id fullName } }
                }
                """,
                token: token
            )
            allUsers = result.users.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
            var map: [Int: String] = [:]
            for team in result.teams {
                for member in team.members {
                    map[member.id] = team.name
                }
            }
            userTeamMap = map
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard let token = authManager.sessionToken, let leadId = teamLeadId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            struct Result: Decodable { let createTeam: Team }
            let _: Result = try await client.fetch(
                query: """
                mutation CreateTeam($input: CreateTeamInput!) {
                    createTeam(input: $input) { id name teamLead { id fullName } members { id fullName } }
                }
                """,
                variables: [
                    "input": [
                        "name": name.trimmingCharacters(in: .whitespaces),
                        "teamLeadId": leadId,
                        "memberIds": Array(selectedMemberIds)
                    ]
                ],
                token: token
            )
            dismiss()
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }
}

// MARK: - MemberRow

private struct MemberRow: View {
    let user: User
    let isSelected: Bool
    let assignedTeamName: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullName)
                        .foregroundStyle(assignedTeamName != nil ? Color.secondary : Color.primary)
                    if let teamName = assignedTeamName {
                        Text(teamName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(assignedTeamName != nil)
    }
}
