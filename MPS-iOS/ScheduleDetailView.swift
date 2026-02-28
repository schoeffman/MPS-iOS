//
//  ScheduleDetailView.swift
//  MPS-iOS
//

import SwiftUI

struct ScheduleDetailView: View {
    let schedule: Schedule

    @Environment(AuthManager.self) var authManager

    @State private var current: Schedule
    @State private var teams: [ScheduleTeam] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showEdit = false

    private let client = GraphQLClient()

    init(schedule: Schedule) {
        self.schedule = schedule
        _current = State(initialValue: schedule)
    }

    var body: some View {
        ZStack { content }
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                EditScheduleView(schedule: current) { updated in
                    current = updated
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if teams.isEmpty {
            ContentUnavailableView(
                "No Teams",
                systemImage: "person.3.slash",
                description: Text("No teams found for this schedule.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text("Week of \(currentWeekLabel)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(teams) { team in
                    Section(team.name) {
                        ForEach(orderedMembers(for: team)) { member in
                            MemberAssignmentRow(
                                member: member,
                                isLead: member.id == team.teamLead.id
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Helpers

    private func orderedMembers(for team: ScheduleTeam) -> [ScheduleMember] {
        let lead = team.members.first { $0.id == team.teamLead.id }
        let others = team.members
            .filter { $0.id != team.teamLead.id }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        return (lead.map { [$0] } ?? []) + others
    }

    private var currentWeekLabel: String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let today = Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: interval.start)
    }

    private func currentWeekDates() -> (start: String, end: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let today = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fmt.timeZone = TimeZone(identifier: "UTC")
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
            let s = fmt.string(from: today)
            return (s, s)
        }
        let start = fmt.string(from: interval.start)
        let end = fmt.string(from: cal.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end)
        return (start, end)
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (startDate, endDate) = currentWeekDates()

            struct FlatAssignment: Decodable { let userId: Int; let projectId: Int }
            struct FlatMember: Decodable { let id: Int; let fullName: String }
            struct FlatTeamLead: Decodable { let id: Int; let fullName: String }
            struct FlatTeam: Decodable {
                let id: Int; let name: String
                let teamLead: FlatTeamLead; let members: [FlatMember]
            }
            struct FlatProject: Decodable { let id: Int; let name: String; let color: String }
            struct Response: Decodable {
                let scheduleAssignments: [FlatAssignment]
                let teams: [FlatTeam]
                let projects: [FlatProject]
            }

            let result: Response = try await client.fetch(
                query: """
                query ScheduleView($scheduleId: Int!, $startDate: String!, $endDate: String!) {
                    scheduleAssignments(scheduleId: $scheduleId, startDate: $startDate, endDate: $endDate) {
                        userId
                        projectId
                    }
                    teams {
                        id name
                        teamLead { id fullName }
                        members { id fullName }
                    }
                    projects {
                        id name color
                    }
                }
                """,
                variables: [
                    "scheduleId": schedule.id,
                    "startDate": startDate,
                    "endDate": endDate
                ],
                token: token
            )

            // Build project lookup: projectId -> project
            let projectMap = Dictionary(uniqueKeysWithValues: result.projects.map { ($0.id, $0) })

            // Build user -> assigned projects map from flat assignments
            var userProjects: [Int: [ScheduleAssignedProject]] = [:]
            for a in result.scheduleAssignments {
                if let p = projectMap[a.projectId] {
                    userProjects[a.userId, default: []].append(
                        ScheduleAssignedProject(id: p.id, name: p.name, color: p.color)
                    )
                }
            }

            // Assemble display model
            teams = result.teams
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { flatTeam in
                    let lead = TeamMember(id: flatTeam.teamLead.id, fullName: flatTeam.teamLead.fullName)
                    let members = flatTeam.members.map { m in
                        ScheduleMember(
                            id: m.id,
                            fullName: m.fullName,
                            assignments: (userProjects[m.id] ?? []).map { ScheduleAssignment(project: $0) }
                        )
                    }
                    return ScheduleTeam(id: flatTeam.id, name: flatTeam.name, teamLead: lead, members: members)
                }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - MemberAssignmentRow

private struct MemberAssignmentRow: View {
    let member: ScheduleMember
    let isLead: Bool

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(member.fullName)
                    .font(.body.weight(.medium))
                if isLead {
                    Text("Lead")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            Text(projectLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(rowBackground)
    }

    private var rowBackground: Color? {
        guard let colorStr = member.assignments.first?.project.color,
              let color = Color(hex: colorStr) else { return nil }
        return color.opacity(0.25)
    }

    private var projectLabel: String {
        guard !member.assignments.isEmpty else { return "None" }
        return member.assignments.map { $0.project.name }.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        ScheduleDetailView(schedule: Schedule(id: 1, name: "Q1 2026", year: 2026, quarter: 1))
    }
    .environment(AuthManager())
}
