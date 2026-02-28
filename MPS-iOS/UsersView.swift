//
//  UsersView.swift
//  MPS-iOS
//

import SwiftUI

struct UsersView: View {
    var embedded = false

    @Environment(AuthManager.self) var authManager

    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedAbility: CraftAbility? = nil
    @State private var showCreate = false
    @State private var showTeams = false
    @State private var showTenure = false
    @State private var showPerformanceCycles = false
    @State private var searchText = ""

    private let client = GraphQLClient()

    private var filtered: [User] {
        users
            .filter { user in
                let matchesAbility = selectedAbility == nil || user.craftAbility == selectedAbility?.rawValue
                let matchesSearch = searchText.isEmpty || user.fullName.localizedCaseInsensitiveContains(searchText)
                return matchesAbility && matchesSearch
            }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    var body: some View {
        if embedded {
            usersContent
        } else {
            NavigationStack {
                usersContent
            }
        }
    }

    private var usersContent: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .navigationTitle("Users")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if embedded {
                    Button { showTeams = true } label: {
                        Image(systemName: "person.3.fill")
                    }
                    Button { showTenure = true } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    Button { showPerformanceCycles = true } label: {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                }
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            CreateUserView()
        }
        .sheet(isPresented: $showTeams) { TeamsView() }
        .sheet(isPresented: $showTenure) { TenureView() }
        .sheet(isPresented: $showPerformanceCycles) { PerformanceCyclesView() }
        .task { await load() }
        .searchable(text: $searchText, prompt: "Search users")
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Subviews

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedAbility == nil) {
                    withAnimation { selectedAbility = nil }
                }
                ForEach(CraftAbility.allCases) { ability in
                    FilterChip(label: ability.displayName, isSelected: selectedAbility == ability) {
                        withAnimation {
                            selectedAbility = selectedAbility == ability ? nil : ability
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "No Users",
                systemImage: "person.slash",
                description: Text(
                    users.isEmpty
                        ? "No users found in this space."
                        : "No users match the selected filter."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filtered) { user in
                NavigationLink(destination: UserDetailView(user: user)) {
                    UserRow(user: user)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Response: Decodable { let users: [User] }
            let result: Response = try await client.fetch(
                query: "{ users { id fullName craftAbility jobLevel craftFocus levelStartDate } }",
                token: token
            )
            users = result.users
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct UserRow: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(user.fullName)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [user.jobLevel, user.craftAbility.displayName]
        if user.craftFocus != "NotApplicable" {
            parts.append(user.craftFocus)
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var displayName: String {
        switch self {
        case "ProductManagement": return "Product Management"
        case "DataScience": return "Data Science"
        default: return self
        }
    }
}

#Preview {
    UsersView()
        .environment(AuthManager())
}
