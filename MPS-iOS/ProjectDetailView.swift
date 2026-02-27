//
//  ProjectDetailView.swift
//  MPS-iOS
//

import SwiftUI

struct ProjectDetailView: View {
    let project: Project

    @Environment(AuthManager.self) var authManager
    @State private var detail: ProjectDetail?
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var error: String?

    private let client = GraphQLClient()

    var body: some View {
        ZStack {
            content
        }
        .navigationTitle(detail?.name ?? project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !project.isSystem {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: {
                        Image(systemName: "pencil")
                    }
                    .disabled(detail == nil)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let d = detail {
                EditProjectView(project: d) { updated in
                    detail = updated
                }
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

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let d = detail {
            List {
                detailSection(d)
                membersSection(d)
                linksSection(d)
                integrationsSection(d)
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView(
                "Unable to Load",
                systemImage: "exclamationmark.triangle",
                description: Text("Could not load project details.")
            )
        }
    }

    private func detailSection(_ d: ProjectDetail) -> some View {
        Section("Details") {
            LabeledContent("Status", value: d.status)
            LabeledContent("Type", value: ProjectType(rawValue: d.projectType)?.displayName ?? d.projectType)
            LabeledContent("Target Date", value: formattedDate(d.targetDate))
            if let dri = d.dri {
                LabeledContent("DRI", value: dri.fullName)
            }
            LabeledContent("Color") {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: d.color) ?? Color.accentColor)
                    .frame(width: 24, height: 24)
            }
        }
    }

    @ViewBuilder
    private func membersSection(_ d: ProjectDetail) -> some View {
        if !d.members.isEmpty {
            Section("Members") {
                ForEach(d.members.sorted {
                    $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
                }) { member in
                    Text(member.fullName)
                }
            }
        }
    }

    @ViewBuilder
    private func linksSection(_ d: ProjectDetail) -> some View {
        if !d.links.isEmpty {
            Section("Links") {
                ForEach(d.links) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            Text(link.url)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func integrationsSection(_ d: ProjectDetail) -> some View {
        if d.jiraProjectKey != nil || d.atlassianProjectKey != nil {
            Section("Integrations") {
                if let jira = d.jiraProjectKey {
                    LabeledContent("Jira", value: jira)
                }
                if let atlassian = d.atlassianProjectKey {
                    LabeledContent("Atlassian", value: atlassian)
                }
            }
        }
    }

    private func formattedDate(_ string: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: string) else { return string }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Response: Decodable { let project: ProjectDetail }
            let result: Response = try await client.fetch(
                query: """
                query GetProject($id: Int!) {
                    project(id: $id) {
                        id name targetDate status color projectType isSystem
                        dri { id fullName }
                        members { id fullName }
                        jiraProjectKey atlassianProjectKey
                        links { id url }
                    }
                }
                """,
                variables: ["id": project.id],
                token: token
            )
            detail = result.project
        } catch {
            self.error = error.localizedDescription
        }
    }
}
