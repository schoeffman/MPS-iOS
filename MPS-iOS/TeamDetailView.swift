//
//  TeamDetailView.swift
//  MPS-iOS
//

import SwiftUI

struct TeamDetailView: View {
    @Environment(AuthManager.self) var authManager
    @State private var currentTeam: Team
    @State private var showEdit = false

    init(team: Team) {
        _currentTeam = State(initialValue: team)
    }

    var body: some View {
        List {
            Section("Members") {
                ForEach(sortedMembers) { member in
                    HStack {
                        Text(member.fullName)
                        Spacer()
                        if member.id == currentTeam.teamLead.id {
                            Text("Lead")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(currentTeam.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditTeamView(team: currentTeam) { updated in
                currentTeam = updated
            }
            .environment(authManager)
        }
    }

    private var sortedMembers: [TeamMember] {
        currentTeam.members.sorted {
            $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
        }
    }
}
