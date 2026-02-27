//
//  StaticProjectDetailView.swift
//  MPS-iOS
//

import SwiftUI

struct StaticProjectDetailView: View {
    let project: Project

    @Environment(AuthManager.self) var authManager
    @State private var detail: ProjectDetail?
    @State private var isLoading = true
    @State private var selectedColor: Color = .accentColor
    @State private var isColorDirty = false
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

    var body: some View {
        ZStack {
            content
        }
        .navigationTitle(detail?.name ?? project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await saveColor() } }
                        .disabled(!isColorDirty || detail == nil)
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
                colorSection
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

    private var colorSection: some View {
        Section("Color") {
            ColorPicker("Project Color", selection: $selectedColor, supportsOpacity: false)
                .onChange(of: selectedColor) { isColorDirty = true }
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
            selectedColor = Color(hex: result.project.color) ?? .accentColor
            isColorDirty = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveColor() async {
        guard let token = authManager.sessionToken, let d = detail else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            struct Result: Decodable { let updateProjectColor: Project }
            let _: Result = try await client.fetch(
                query: """
                mutation UpdateProjectColor($id: Int!, $color: String!) {
                    updateProjectColor(id: $id, color: $color) { id color }
                }
                """,
                variables: ["id": d.id, "color": hexString(from: selectedColor)],
                token: token
            )
            isColorDirty = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func hexString(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
