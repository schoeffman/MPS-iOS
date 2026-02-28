//
//  AccountSettingsView.swift
//  MPS-iOS
//

import SwiftUI

struct AccountSettingsView: View {
    @Environment(AuthManager.self) var authManager

    @State private var profile: ProfileInfo?
    @State private var spaces: [SpaceInfo] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showSignOutAllAlert = false
    @State private var showDeleteAlert = false

    private let client = GraphQLClient()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        profileSection
                        spacesSection
                        dangerSection
                    }
                }
            }
            .navigationTitle("Account Settings")
            .task { await load() }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .alert("Sign Out of All Devices", isPresented: $showSignOutAllAlert) {
                Button("Sign Out All", role: .destructive) {
                    Task { await signOutAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will end all active sessions across every device.")
            }
            .alert("Delete Account", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section("Profile") {
            if let profile {
                HStack(spacing: 14) {
                    avatarView(for: profile)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name)
                            .font(.body.weight(.medium))
                        Text(profile.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var spacesSection: some View {
        Section("Spaces") {
            if spaces.isEmpty {
                Text("No spaces found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(spaces) { space in
                    Button {
                        authManager.switchSpace(space.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(space.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(space.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if space.isOwner {
                                Text("Owner")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                            if authManager.activeSpaceId == space.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dangerSection: some View {
        Section("Danger Zone") {
            Button {
                showSignOutAllAlert = true
            } label: {
                Label("Sign Out of All Devices", systemImage: "rectangle.portrait.and.arrow.right.fill")
                    .foregroundStyle(.orange)
            }

            Button {
                showDeleteAlert = true
            } label: {
                Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private func avatarView(for profile: ProfileInfo) -> some View {
        if let imageURL = profile.image.flatMap({ URL(string: $0) }) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialsView(for: profile.name)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            initialsView(for: profile.name)
                .frame(width: 48, height: 48)
        }
    }

    private func initialsView(for name: String) -> some View {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
        return Circle()
            .fill(Color.accentColor.opacity(0.2))
            .overlay {
                Text(initials)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct AuthUser: Decodable { let name: String; let email: String; let image: String? }
            struct SessionInfo: Decodable { let user: AuthUser }
            struct SpaceResponse: Decodable { let id: String; let name: String; let email: String; let isOwner: Bool }
            struct Response: Decodable { let me: SessionInfo?; let mySpaces: [SpaceResponse] }

            let result: Response = try await client.fetch(
                query: """
                {
                    me { user { name email image } }
                    mySpaces { id name email isOwner }
                }
                """,
                token: token
            )
            if let user = result.me?.user {
                profile = ProfileInfo(name: user.name, email: user.email, image: user.image)
            }
            spaces = result.mySpaces.map { SpaceInfo(id: $0.id, name: $0.name, email: $0.email, isOwner: $0.isOwner) }
            if authManager.activeSpaceId == nil, let first = spaces.first {
                authManager.switchSpace(first.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func signOutAll() async {
        guard let token = authManager.sessionToken else { return }
        let url = URL(string: "https://mps-p.up.railway.app/api/auth/revoke-sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await authManager.signOut()
    }

    private func deleteAccount() async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Response: Decodable { let deleteMyAccount: Bool }
            let _: Response = try await client.fetch(
                query: "mutation { deleteMyAccount }",
                token: token
            )
            await authManager.signOut()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Models

    private struct ProfileInfo {
        let name: String
        let email: String
        let image: String?
    }

    private struct SpaceInfo: Identifiable {
        let id: String
        let name: String
        let email: String
        let isOwner: Bool
    }
}

#Preview {
    AccountSettingsView()
        .environment(AuthManager())
}
