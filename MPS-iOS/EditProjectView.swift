//
//  EditProjectView.swift
//  MPS-iOS
//

import SwiftUI

struct EditProjectView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) private var dismiss

    let project: ProjectDetail
    let onSave: (ProjectDetail) -> Void

    @State private var name: String
    @State private var status: ProjectStatus
    @State private var projectType: ProjectType
    @State private var targetDate: Date
    @State private var driId: Int?
    @State private var color: Color
    @State private var jiraKey: String
    @State private var atlassianKey: String

    @State private var allUsers: [User] = []
    @State private var isLoadingUsers = false
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

    init(project: ProjectDetail, onSave: @escaping (ProjectDetail) -> Void) {
        self.project = project
        self.onSave = onSave
        _name = State(initialValue: project.name)
        _status = State(initialValue: ProjectStatus(rawValue: project.status) ?? .Explore)
        _projectType = State(initialValue: ProjectType(rawValue: project.projectType) ?? .Other)
        _driId = State(initialValue: project.dri?.id)
        _color = State(initialValue: Color(hex: project.color) ?? Color.accentColor)
        _jiraKey = State(initialValue: project.jiraProjectKey ?? "")
        _atlassianKey = State(initialValue: project.atlassianProjectKey ?? "")
        _targetDate = State(initialValue: {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.date(from: project.targetDate) ?? Date()
        }())
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                detailsSection
                driSection
                colorSection
                integrationsSection
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
            .task { await loadUsers() }
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
            TextField("Name", text: $name)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Status", selection: $status) {
                ForEach(ProjectStatus.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            Picker("Type", selection: $projectType) {
                ForEach(ProjectType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            DatePicker("Target Date", selection: $targetDate, displayedComponents: .date)
        }
    }

    @ViewBuilder
    private var driSection: some View {
        Section("DRI") {
            if isLoadingUsers {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Picker("DRI", selection: $driId) {
                    Text("None").tag(Optional<Int>.none)
                    ForEach(allUsers, id: \.id) { user in
                        Text(user.fullName).tag(Optional<Int>.some(user.id))
                    }
                }
            }
        }
    }

    private var colorSection: some View {
        Section("Color") {
            ColorPicker("Project Color", selection: $color, supportsOpacity: false)
        }
    }

    private var integrationsSection: some View {
        Section("Integrations") {
            TextField("Jira Project Key", text: $jiraKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            TextField("Atlassian Project Key", text: $atlassianKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if isSaving {
            ProgressView()
        } else {
            Button("Save") { Task { await save() } }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func loadUsers() async {
        guard let token = authManager.sessionToken else { return }
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            struct Response: Decodable { let users: [User] }
            let result: Response = try await client.fetch(
                query: "{ users { id fullName craftAbility jobLevel craftFocus levelStartDate } }",
                token: token
            )
            allUsers = result.users.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            struct Result: Decodable { let updateProject: ProjectDetail }
            var input: [String: Any] = [
                "name": name.trimmingCharacters(in: .whitespaces),
                "targetDate": targetDate.formatted(.iso8601.year().month().day()),
                "status": status.rawValue,
                "color": hexString(from: color),
                "projectType": projectType.rawValue,
            ]
            if let id = driId { input["driId"] = id }
            let jira = jiraKey.trimmingCharacters(in: .whitespaces)
            if !jira.isEmpty { input["jiraProjectKey"] = jira }
            let atlassian = atlassianKey.trimmingCharacters(in: .whitespaces)
            if !atlassian.isEmpty { input["atlassianProjectKey"] = atlassian }

            let result: Result = try await client.fetch(
                query: """
                mutation UpdateProject($id: Int!, $input: UpdateProjectInput!) {
                    updateProject(id: $id, input: $input) {
                        id name targetDate status color projectType isSystem
                        dri { id fullName }
                        members { id fullName }
                        jiraProjectKey atlassianProjectKey
                        links { id url }
                    }
                }
                """,
                variables: ["id": project.id, "input": input],
                token: token
            )
            onSave(result.updateProject)
            dismiss()
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }

    private func hexString(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
