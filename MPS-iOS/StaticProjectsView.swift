//
//  StaticProjectsView.swift
//  MPS-iOS
//

import SwiftUI

struct StaticProjectsView: View {
    var embedded = false

    @Environment(AuthManager.self) var authManager

    @State private var projects: [Project] = []
    @State private var isLoading = false
    @State private var error: String?

    private let client = GraphQLClient()

    private var sorted: [Project] {
        projects
            .filter(\.isSystem)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if embedded {
            staticContent
        } else {
            NavigationStack { staticContent }
        }
    }

    private var staticContent: some View {
        content
            .navigationTitle("Static Projects")
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
                "No Static Projects",
                systemImage: "folder.fill.badge.gearshape",
                description: Text("No static projects found in this space.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(sorted) { project in
                NavigationLink(destination: StaticProjectDetailView(project: project)) {
                    ProjectRow(project: project)
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
            struct Response: Decodable { let projects: [Project] }
            let result: Response = try await client.fetch(
                query: "{ projects { id name targetDate status color projectType isSystem } }",
                token: token
            )
            projects = result.projects
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }
}
