//
//  SpaceSettingsView.swift
//  MPS-iOS
//

import SwiftUI

struct SpaceSettingsView: View {
    @Environment(AuthManager.self) var authManager

    @State private var isLoading = true
    @State private var isOwner = true
    @State private var error: String?

    // Owner state
    @State private var limits: [LimitInfo] = []
    @State private var jiraConfig: JiraConfigInfo?
    @State private var members: [SpaceMemberInfo] = []

    // Non-owner state
    @State private var ownerName = ""
    @State private var ownerEmail = ""
    @State private var showLeaveAlert = false

    // Jira form
    @State private var showJiraForm = false
    @State private var jiraDomain = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jiraStoryPoints = ""
    @State private var jiraError: String?
    @State private var jiraSaving = false

    // Member add form
    @State private var newMemberEmail = ""
    @State private var addingMember = false
    @State private var memberError: String?

    private let client = GraphQLClient()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isOwner {
                    List {
                        timeLimitsSection
                        jiraSection
                        membersSection
                    }
                } else {
                    List {
                        thisSpaceSection
                    }
                }
            }
            .navigationTitle("Space Settings")
            .task { await load() }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .alert("Leave Space", isPresented: $showLeaveAlert) {
                Button("Leave", role: .destructive) {
                    Task { await leaveSpace() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will lose access to \(ownerName)'s data. The owner can re-add you later.")
            }
        }
    }

    // MARK: - Owner Sections

    private var timeLimitsSection: some View {
        Section {
            Text("Set the expected maximum time at each job level in months. A value of 0 means no limit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach($limits) { $limit in
                LimitSliderRow(limit: $limit) { months in
                    Task { await saveLimit(jobLevel: limit.jobLevel, months: months) }
                }
            }
        } header: {
            Text("Time in Level Limits")
        }
    }

    private var jiraSection: some View {
        Section("Jira Integration") {
            if let config = jiraConfig, !showJiraForm {
                jiraDetailView(config: config)
            } else {
                jiraFormView
            }
        }
    }

    @ViewBuilder
    private func jiraDetailView(config: JiraConfigInfo) -> some View {
        LabeledContent("Domain") {
            Text("\(config.domain).atlassian.net").foregroundStyle(.secondary)
        }
        LabeledContent("Email") {
            Text(config.email).foregroundStyle(.secondary)
        }
        LabeledContent("API Token") {
            Text("••••••••").foregroundStyle(.secondary)
        }
        LabeledContent("Story Points Field") {
            Text(config.storyPointsFieldId ?? "Not configured").foregroundStyle(.secondary)
        }
        HStack {
            Button("Update") {
                jiraDomain = config.domain
                jiraEmail = config.email
                jiraToken = ""
                jiraStoryPoints = config.storyPointsFieldId ?? ""
                showJiraForm = true
            }
            Spacer()
            Button("Remove", role: .destructive) {
                Task { await removeJiraConfig() }
            }
        }
    }

    @ViewBuilder
    private var jiraFormView: some View {
        if jiraConfig == nil {
            Text("Connect your Jira Cloud instance to view issues on project pages.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        HStack {
            TextField("mycompany", text: $jiraDomain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Text(".atlassian.net")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        TextField("Email", text: $jiraEmail)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        SecureField("API Token", text: $jiraToken)
        TextField("Story Points Field ID (optional)", text: $jiraStoryPoints)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        if let err = jiraError {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
        }
        Button(jiraSaving ? "Saving…" : "Save Jira Config") {
            Task { await saveJiraConfig() }
        }
        .disabled(jiraSaving || jiraDomain.isEmpty || jiraEmail.isEmpty || jiraToken.isEmpty)
        if showJiraForm {
            Button("Cancel") {
                showJiraForm = false
                jiraError = nil
            }
            .foregroundStyle(.secondary)
        }
    }

    private var membersSection: some View {
        Section("Members") {
            Text("Invite others by email to give them full access to your space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                TextField("user@example.com", text: $newMemberEmail)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(addingMember ? "Adding…" : "Add Member") {
                    Task { await addMember() }
                }
                .disabled(addingMember || newMemberEmail.isEmpty)
            }
            if let err = memberError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(members) { member in
                SpaceMemberRow(member: member) {
                    Task { await removeMember(authId: member.authId) }
                }
            }
        }
    }

    // MARK: - Non-Owner Section

    private var thisSpaceSection: some View {
        Section("This Space") {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(ownerName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownerName)
                        .font(.body.weight(.medium))
                    Text(ownerEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            Button("Leave Space", role: .destructive) {
                showLeaveAlert = true
            }
        }
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct SpaceRow: Decodable { let id: String; let name: String; let email: String; let isOwner: Bool }
            struct LoadResponse: Decodable {
                let mySpaces: [SpaceRow]
                let jobLevelLimits: [LimitInfo]
                let jiraConfig: JiraConfigInfo?
                let spaceMembers: [SpaceMemberInfo]
            }
            let result: LoadResponse = try await client.fetch(
                query: """
                {
                    mySpaces { id name email isOwner }
                    jobLevelLimits { jobLevel limitMonths }
                    jiraConfig { id domain email hasToken storyPointsFieldId }
                    spaceMembers { id authId email name image }
                }
                """,
                token: token
            )

            let activeId = authManager.activeSpaceId
            var activeSpace = result.mySpaces.first { $0.id == activeId }
            if activeSpace == nil {
                activeSpace = result.mySpaces.first
                if let first = activeSpace { authManager.switchSpace(first.id) }
            }

            isOwner = activeSpace?.isOwner ?? true

            if isOwner {
                let order = ["Junior", "Mid", "Senior", "Staff", "Principal"]
                limits = order.map { level in
                    result.jobLevelLimits.first { $0.jobLevel == level } ?? LimitInfo(jobLevel: level, limitMonths: 0)
                }
                jiraConfig = result.jiraConfig
                members = result.spaceMembers
            } else {
                ownerName = activeSpace?.name ?? ""
                ownerEmail = activeSpace?.email ?? ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveLimit(jobLevel: String, months: Int) async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Result: Decodable { let setJobLevelLimit: LimitInfo }
            let result: Result = try await client.fetch(
                query: "mutation($jl: JobLevel!, $m: Int!) { setJobLevelLimit(jobLevel: $jl, limitMonths: $m) { jobLevel limitMonths } }",
                variables: ["jl": jobLevel, "m": months],
                token: token
            )
            if let idx = limits.firstIndex(where: { $0.jobLevel == jobLevel }) {
                limits[idx] = result.setJobLevelLimit
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveJiraConfig() async {
        guard let token = authManager.sessionToken else { return }
        jiraSaving = true
        jiraError = nil
        defer { jiraSaving = false }
        do {
            struct Result: Decodable { let saveJiraConfig: JiraConfigInfo }
            var vars: [String: Any] = ["domain": jiraDomain, "email": jiraEmail, "apiToken": jiraToken]
            if !jiraStoryPoints.isEmpty { vars["storyPointsFieldId"] = jiraStoryPoints }
            let result: Result = try await client.fetch(
                query: """
                mutation($domain: String!, $email: String!, $apiToken: String!, $storyPointsFieldId: String) {
                    saveJiraConfig(domain: $domain, email: $email, apiToken: $apiToken, storyPointsFieldId: $storyPointsFieldId) {
                        id domain email hasToken storyPointsFieldId
                    }
                }
                """,
                variables: vars,
                token: token
            )
            jiraConfig = result.saveJiraConfig
            showJiraForm = false
            jiraDomain = ""; jiraEmail = ""; jiraToken = ""; jiraStoryPoints = ""
        } catch {
            jiraError = error.localizedDescription
        }
    }

    private func removeJiraConfig() async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Result: Decodable { let removeJiraConfig: Bool }
            let _: Result = try await client.fetch(query: "mutation { removeJiraConfig }", token: token)
            jiraConfig = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addMember() async {
        guard let token = authManager.sessionToken else { return }
        addingMember = true
        memberError = nil
        defer { addingMember = false }
        do {
            struct Result: Decodable { let addSpaceMember: SpaceMemberInfo }
            let result: Result = try await client.fetch(
                query: "mutation($email: String!) { addSpaceMember(email: $email) { id authId email name image } }",
                variables: ["email": newMemberEmail],
                token: token
            )
            members.append(result.addSpaceMember)
            newMemberEmail = ""
        } catch {
            memberError = error.localizedDescription
        }
    }

    private func removeMember(authId: String) async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Result: Decodable { let removeSpaceMember: Bool }
            let _: Result = try await client.fetch(
                query: "mutation($authId: String!) { removeSpaceMember(memberAuthId: $authId) }",
                variables: ["authId": authId],
                token: token
            )
            members.removeAll { $0.authId == authId }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func leaveSpace() async {
        guard let token = authManager.sessionToken,
              let ownerAuthId = authManager.activeSpaceId else { return }
        do {
            struct Result: Decodable { let leaveSpace: Bool }
            let _: Result = try await client.fetch(
                query: "mutation($ownerAuthId: String!) { leaveSpace(ownerAuthId: $ownerAuthId) }",
                variables: ["ownerAuthId": ownerAuthId],
                token: token
            )
            authManager.clearActiveSpace()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Models

    fileprivate struct LimitInfo: Decodable, Identifiable {
        var id: String { jobLevel }
        var jobLevel: String
        var limitMonths: Int
    }

    fileprivate struct JiraConfigInfo: Decodable {
        let id: Int
        let domain: String
        let email: String
        let hasToken: Bool
        let storyPointsFieldId: String?
    }

    fileprivate struct SpaceMemberInfo: Decodable, Identifiable {
        let id: Int
        let authId: String
        let email: String
        let name: String
        let image: String?
    }
}

// MARK: - Supporting Views

private struct LimitSliderRow: View {
    @Binding var limit: SpaceSettingsView.LimitInfo
    let onCommit: (Int) -> Void

    @State private var sliderValue: Double

    init(limit: Binding<SpaceSettingsView.LimitInfo>, onCommit: @escaping (Int) -> Void) {
        _limit = limit
        self.onCommit = onCommit
        _sliderValue = State(initialValue: Double(limit.wrappedValue.limitMonths))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(limit.jobLevel)
                    .font(.body.weight(.medium))
                Spacer()
                Text(sliderValue == 0 ? "No limit" : "\(Int(sliderValue)) month\(Int(sliderValue) == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $sliderValue, in: 0...60, step: 1) { editing in
                if !editing {
                    let months = Int(sliderValue)
                    limit.limitMonths = months
                    onCommit(months)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SpaceMemberRow: View {
    let member: SpaceSettingsView.SpaceMemberInfo
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.body.weight(.medium))
                Text(member.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let imageURL = member.image.flatMap({ URL(string: $0) }) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    initialsCircle
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            initialsCircle
                .frame(width: 36, height: 36)
        }
    }

    private var initialsCircle: some View {
        let initial = String(member.name.prefix(1)).uppercased()
        return Circle()
            .fill(Color(.systemGray5))
            .overlay {
                Text(initial)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    SpaceSettingsView()
        .environment(AuthManager())
}
