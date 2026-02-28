//
//  TeamsView.swift
//  MPS-iOS
//

import SwiftUI

struct TeamsView: View {
    var embedded = false

    @Environment(AuthManager.self) var authManager

    @State private var teams: [Team] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreate = false

    private let client = GraphQLClient()

    private var sorted: [Team] {
        teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if embedded {
            teamsContent
        } else {
            NavigationStack {
                teamsContent
            }
        }
    }

    private var teamsContent: some View {
        content
            .navigationTitle("Teams")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                CreateTeamView()
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

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sorted.isEmpty {
            ContentUnavailableView(
                "No Teams",
                systemImage: "person.3.slash",
                description: Text("No teams found in this space.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(sorted) { team in
                NavigationLink(destination: TeamDetailView(team: team)) {
                    TeamRow(team: team)
                }
            }
            .listStyle(.plain)
        }
    }

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Response: Decodable { let teams: [Team] }
            let result: Response = try await client.fetch(
                query: "{ teams { id name teamLead { id fullName } members { id fullName } } }",
                token: token
            )
            teams = result.teams
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - TeamRow

private struct TeamRow: View {
    let team: Team

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(team.name)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let count = team.members.count
        let memberLabel = count == 1 ? "1 member" : "\(count) members"
        return "Led by \(team.teamLead.fullName) · \(memberLabel)"
    }
}

#Preview {
    TeamsView()
        .environment(AuthManager())
}
