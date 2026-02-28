//
//  ProjectsView.swift
//  MPS-iOS
//

import SwiftUI

struct ProjectsView: View {
    var embedded = false

    @Environment(AuthManager.self) var authManager

    @State private var projects: [Project] = []
    @State private var selectedStatus: ProjectStatus? = nil
    @State private var isLoading = false
    @State private var error: String?

    private let client = GraphQLClient()

    private var filtered: [Project] {
        projects
            .filter { !$0.isSystem && (selectedStatus == nil || $0.status == selectedStatus?.rawValue) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if embedded {
            projectsContent
        } else {
            NavigationStack { projectsContent }
        }
    }

    private var projectsContent: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .navigationTitle("Projects")
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedStatus == nil) {
                    withAnimation { selectedStatus = nil }
                }
                ForEach(ProjectStatus.allCases) { status in
                    FilterChip(label: status.rawValue, isSelected: selectedStatus == status) {
                        withAnimation {
                            selectedStatus = selectedStatus == status ? nil : status
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
                "No Projects",
                systemImage: "folder",
                description: Text(
                    projects.isEmpty
                        ? "No projects found in this space."
                        : "No projects match the selected filter."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filtered) { project in
                NavigationLink(destination: ProjectDetailView(project: project)) {
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

// MARK: - ProjectRow

struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let type = ProjectType(rawValue: project.projectType)?.displayName ?? project.projectType
        return "\(project.status) · \(type)"
    }
}

// MARK: - Color+ProjectColor

extension Color {
    init?(hex: String) {
        // Named color strings used by the server
        switch hex.lowercased() {
        case "blue":   self = .blue;   return
        case "green":  self = .green;  return
        case "orange": self = .orange; return
        case "purple": self = .purple; return
        case "cyan":   self = .cyan;   return
        case "teal":   self = .teal;   return
        case "red":    self = .red;    return
        case "yellow": self = .yellow; return
        case "pink":   self = .pink;   return
        case "indigo": self = .indigo; return
        case "mint":   self = .mint;   return
        case "amber":  self = Color(red: 245/255, green: 158/255, blue: 11/255); return
        default: break
        }
        // Hex string fallback (#RRGGBB or RRGGBB)
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ProjectsView()
        .environment(AuthManager())
}
