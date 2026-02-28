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
    @State private var allProjects: [ScheduleAssignedProject] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showEdit = false
    @State private var editingMember: ScheduleMember?
    @State private var showWeekPicker = false
    @State private var showOnCallGaps = false
    @State private var showGraphs = false
    @State private var allQuarterAssignments: [(userId: Int, projectId: Int, weekStart: String)] = []
    @State private var projectTypes: [Int: String] = [:]
    @State private var uncoveredWeeks: [Date] = []
    @State private var isMultiSelectMode = false
    @State private var selectedMemberIds: Set<Int> = []
    @State private var showBulkProjectPicker = false
    @State private var teamForBulkAssign: ScheduleTeam?
    @State private var selectedWeekStart: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }()

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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showGraphs = true } label: {
                        Image(systemName: "chart.pie.fill")
                    }
                    Button { showEdit = true } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showGraphs) {
                ScheduleGraphsView(
                    assignments: allQuarterAssignments,
                    projects: allProjects,
                    projectTypes: projectTypes,
                    totalMemberWeeks: totalMemberWeeks
                )
            }
            .sheet(isPresented: $showEdit) {
                EditScheduleView(schedule: current) { updated in
                    current = updated
                }
            }
            .sheet(item: $editingMember) { member in
                ProjectPickerView(member: member, projects: allProjects) { project in
                    Task { await setAssignment(for: member, project: project) }
                }
            }
            .sheet(isPresented: $showOnCallGaps) {
                OnCallGapsView(weeks: uncoveredWeeks) { week in
                    selectedWeekStart = week
                }
            }
            .sheet(isPresented: $showWeekPicker) {
                WeekPickerView(
                    weeks: weeksInQuarter,
                    selected: selectedWeekStart
                ) { week in
                    selectedWeekStart = week
                }
            }
            .sheet(isPresented: $showBulkProjectPicker) {
                BulkProjectPickerView(projects: allProjects) { project in
                    Task { await bulkAssign(project: project) }
                }
            }
            .sheet(item: $teamForBulkAssign) { team in
                BulkProjectPickerView(projects: allProjects) { project in
                    Task { await bulkAssignTeam(team: team, project: project) }
                }
            }
            .task { await load() }
            .onChange(of: selectedWeekStart) { _, _ in
                isMultiSelectMode = false
                selectedMemberIds = []
                Task { await loadAssignments() }
            }
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
                if !uncoveredWeeks.isEmpty {
                    Section {
                        Button { showOnCallGaps = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("On Call coverage missing")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    let count = uncoveredWeeks.count
                                    Text("\(count) week\(count == 1 ? "" : "s") without an On Call assignment")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button { showWeekPicker = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                            Text("Week of \(weekLabel(for: selectedWeekStart))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    let holidays = HolidayHelper.holidaysInWeek(weekStart: selectedWeekStart)
                    if !holidays.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundStyle(.yellow)
                            Text(holidays.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    Button {
                        isMultiSelectMode.toggle()
                        if !isMultiSelectMode { selectedMemberIds = [] }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isMultiSelectMode ? "xmark.circle.fill" : "checkmark.circle")
                                .foregroundStyle(isMultiSelectMode ? Color.red : Color.secondary)
                            Text(isMultiSelectMode ? "Cancel Selection" : "Multi-Select")
                                .font(.subheadline)
                                .foregroundStyle(isMultiSelectMode ? Color.red : Color.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isMultiSelectMode && !selectedMemberIds.isEmpty {
                        Button { showBulkProjectPicker = true } label: {
                            HStack {
                                Text("Assign Project (\(selectedMemberIds.count) selected)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(teams) { team in
                    Section {
                        ForEach(orderedMembers(for: team)) { member in
                            MemberAssignmentRow(
                                member: member,
                                isLead: member.id == team.teamLead.id,
                                isMultiSelectMode: isMultiSelectMode,
                                isSelected: selectedMemberIds.contains(member.id)
                            ) {
                                if isMultiSelectMode {
                                    if selectedMemberIds.contains(member.id) {
                                        selectedMemberIds.remove(member.id)
                                    } else {
                                        selectedMemberIds.insert(member.id)
                                    }
                                } else {
                                    editingMember = member
                                }
                            }
                        }
                    } header: {
                        Button { teamForBulkAssign = team } label: {
                            HStack(spacing: 4) {
                                Text(team.name)
                                Image(systemName: "square.and.pencil")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
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

    private func weekLabel(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }

    private func isoDate(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private var weeksInQuarter: [Date] {
        let q = current.quarter
        let year = current.year
        let startMonth = (q - 1) * 3 + 1
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        guard
            let quarterStart = cal.date(from: DateComponents(year: year, month: startMonth, day: 1)),
            let quarterEnd = cal.date(from: DateComponents(year: year, month: startMonth + 3, day: 1)),
            var weekStart = cal.dateInterval(of: .weekOfYear, for: quarterStart)?.start
        else { return [] }
        var weeks: [Date] = []
        while weekStart < quarterEnd {
            weeks.append(weekStart)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    private var totalMemberWeeks: Int {
        let memberCount = Set(teams.flatMap { $0.members.map { $0.id } }).count
        return memberCount * weeksInQuarter.count
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var cal = Calendar(identifier: .gregorian)
            cal.firstWeekday = 2
            let startDate = isoDate(selectedWeekStart)
            let endDate = isoDate(cal.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart)

            let weeks = weeksInQuarter
            let quarterStartDate = weeks.first.map { isoDate($0) } ?? startDate
            let quarterEndDate = weeks.last.map { isoDate($0) } ?? endDate

            struct FlatAssignment: Decodable { let userId: Int; let projectId: Int }
            struct FlatQuarterAssignment: Decodable { let userId: Int; let projectId: Int; let weekStart: String }
            struct FlatMember: Decodable { let id: Int; let fullName: String }
            struct FlatTeamLead: Decodable { let id: Int; let fullName: String }
            struct FlatTeam: Decodable {
                let id: Int; let name: String
                let teamLead: FlatTeamLead; let members: [FlatMember]
            }
            struct FlatProject: Decodable { let id: Int; let name: String; let color: String; let projectType: String }
            struct Response: Decodable {
                let scheduleAssignments: [FlatAssignment]
                let quarterAssignments: [FlatQuarterAssignment]
                let teams: [FlatTeam]
                let projects: [FlatProject]
            }

            let result: Response = try await client.fetch(
                query: """
                query ScheduleView($scheduleId: Int!, $startDate: String!, $endDate: String!, $qStart: String!, $qEnd: String!) {
                    scheduleAssignments(scheduleId: $scheduleId, startDate: $startDate, endDate: $endDate) {
                        userId projectId
                    }
                    quarterAssignments: scheduleAssignments(scheduleId: $scheduleId, startDate: $qStart, endDate: $qEnd) {
                        userId projectId weekStart
                    }
                    teams {
                        id name
                        teamLead { id fullName }
                        members { id fullName }
                    }
                    projects { id name color projectType }
                }
                """,
                variables: [
                    "scheduleId": schedule.id,
                    "startDate": startDate,
                    "endDate": endDate,
                    "qStart": quarterStartDate,
                    "qEnd": quarterEndDate
                ],
                token: token
            )

            let projectMap = Dictionary(uniqueKeysWithValues: result.projects.map { ($0.id, $0) })
            var userProjects: [Int: [ScheduleAssignedProject]] = [:]
            for a in result.scheduleAssignments {
                if let p = projectMap[a.projectId] {
                    userProjects[a.userId, default: []].append(
                        ScheduleAssignedProject(id: p.id, name: p.name, color: p.color)
                    )
                }
            }

            allProjects = result.projects
                .map { ScheduleAssignedProject(id: $0.id, name: $0.name, color: $0.color) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            projectTypes = Dictionary(uniqueKeysWithValues: result.projects.map { ($0.id, $0.projectType) })

            allQuarterAssignments = result.quarterAssignments
                .map { (userId: $0.userId, projectId: $0.projectId, weekStart: $0.weekStart) }

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

            computeUncoveredWeeks()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func computeUncoveredWeeks() {
        guard let onCall = allProjects.first(where: { $0.name.localizedCaseInsensitiveCompare("On Call") == .orderedSame }) else {
            uncoveredWeeks = []
            return
        }
        let coveredWeekStarts = Set(allQuarterAssignments.filter { $0.projectId == onCall.id }.map { $0.weekStart })
        uncoveredWeeks = weeksInQuarter.filter { !coveredWeekStarts.contains(isoDate($0)) }
    }

    private func loadAssignments() async {
        guard let token = authManager.sessionToken else { return }
        let startDate = isoDate(selectedWeekStart)
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let endDate = isoDate(cal.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart)
        do {
            struct FlatAssignment: Decodable { let userId: Int; let projectId: Int }
            struct Response: Decodable { let scheduleAssignments: [FlatAssignment] }
            let result: Response = try await client.fetch(
                query: """
                query Assignments($scheduleId: Int!, $startDate: String!, $endDate: String!) {
                    scheduleAssignments(scheduleId: $scheduleId, startDate: $startDate, endDate: $endDate) {
                        userId projectId
                    }
                }
                """,
                variables: ["scheduleId": schedule.id, "startDate": startDate, "endDate": endDate],
                token: token
            )
            let projectMap = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
            var userProjects: [Int: [ScheduleAssignedProject]] = [:]
            for a in result.scheduleAssignments {
                if let p = projectMap[a.projectId] {
                    userProjects[a.userId, default: []].append(p)
                }
            }
            teams = teams.map { team in
                let updatedMembers = team.members.map { m in
                    ScheduleMember(
                        id: m.id,
                        fullName: m.fullName,
                        assignments: (userProjects[m.id] ?? []).map { ScheduleAssignment(project: $0) }
                    )
                }
                return ScheduleTeam(id: team.id, name: team.name, teamLead: team.teamLead, members: updatedMembers)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setAssignment(for member: ScheduleMember, project: ScheduleAssignedProject?) async {
        guard let token = authManager.sessionToken else { return }
        let weekStart = isoDate(selectedWeekStart)
        do {
            struct Result: Decodable { let setScheduleAssignment: AssignmentResult? }
            struct AssignmentResult: Decodable { let id: Int }
            var variables: [String: Any] = [
                "scheduleId": schedule.id,
                "userId": member.id,
                "weekStart": weekStart
            ]
            if let project { variables["projectId"] = project.id } else { variables["projectId"] = NSNull() }
            let _: Result = try await client.fetch(
                query: """
                mutation SetAssignment($scheduleId: Int!, $userId: Int!, $weekStart: String!, $projectId: Int) {
                    setScheduleAssignment(scheduleId: $scheduleId, userId: $userId, weekStart: $weekStart, projectId: $projectId) {
                        id
                    }
                }
                """,
                variables: variables,
                token: token
            )
            teams = teams.map { team in
                let updatedMembers = team.members.map { m -> ScheduleMember in
                    guard m.id == member.id else { return m }
                    return ScheduleMember(
                        id: m.id,
                        fullName: m.fullName,
                        assignments: project.map { [ScheduleAssignment(project: $0)] } ?? []
                    )
                }
                return ScheduleTeam(id: team.id, name: team.name, teamLead: team.teamLead, members: updatedMembers)
            }

            // Keep quarter assignments in sync
            allQuarterAssignments.removeAll { $0.userId == member.id && $0.weekStart == weekStart }
            if let project {
                allQuarterAssignments.append((userId: member.id, projectId: project.id, weekStart: weekStart))
            }
            computeUncoveredWeeks()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func bulkAssign(project: ScheduleAssignedProject?) async {
        guard let token = authManager.sessionToken else { return }
        let weekStart = isoDate(selectedWeekStart)
        let memberIds = Array(selectedMemberIds)
        do {
            struct BulkResult: Decodable { let bulkSetScheduleAssignments: Bool }
            let assignments: [[String: Any]] = memberIds.map { userId in
                var a: [String: Any] = ["userId": userId, "weekStart": weekStart]
                if let project { a["projectId"] = project.id } else { a["projectId"] = NSNull() }
                return a
            }
            let _: BulkResult = try await client.fetch(
                query: """
                mutation BulkAssign($scheduleId: Int!, $assignments: [BulkAssignmentInput!]!) {
                    bulkSetScheduleAssignments(scheduleId: $scheduleId, assignments: $assignments)
                }
                """,
                variables: ["scheduleId": schedule.id, "assignments": assignments],
                token: token
            )
            teams = teams.map { team in
                let updatedMembers = team.members.map { m -> ScheduleMember in
                    guard memberIds.contains(m.id) else { return m }
                    return ScheduleMember(
                        id: m.id,
                        fullName: m.fullName,
                        assignments: project.map { [ScheduleAssignment(project: $0)] } ?? []
                    )
                }
                return ScheduleTeam(id: team.id, name: team.name, teamLead: team.teamLead, members: updatedMembers)
            }
            for userId in memberIds {
                allQuarterAssignments.removeAll { $0.userId == userId && $0.weekStart == weekStart }
                if let project {
                    allQuarterAssignments.append((userId: userId, projectId: project.id, weekStart: weekStart))
                }
            }
            computeUncoveredWeeks()
            isMultiSelectMode = false
            selectedMemberIds = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func bulkAssignTeam(team: ScheduleTeam, project: ScheduleAssignedProject?) async {
        guard let token = authManager.sessionToken else { return }
        let weekStart = isoDate(selectedWeekStart)
        let memberIds = team.members.map { $0.id }
        do {
            struct BulkResult: Decodable { let bulkSetScheduleAssignments: Bool }
            let assignments: [[String: Any]] = memberIds.map { userId in
                var a: [String: Any] = ["userId": userId, "weekStart": weekStart]
                if let project { a["projectId"] = project.id } else { a["projectId"] = NSNull() }
                return a
            }
            let _: BulkResult = try await client.fetch(
                query: """
                mutation BulkAssign($scheduleId: Int!, $assignments: [BulkAssignmentInput!]!) {
                    bulkSetScheduleAssignments(scheduleId: $scheduleId, assignments: $assignments)
                }
                """,
                variables: ["scheduleId": schedule.id, "assignments": assignments],
                token: token
            )
            teams = teams.map { t in
                guard t.id == team.id else { return t }
                let updatedMembers = t.members.map { m in
                    ScheduleMember(
                        id: m.id,
                        fullName: m.fullName,
                        assignments: project.map { [ScheduleAssignment(project: $0)] } ?? []
                    )
                }
                return ScheduleTeam(id: t.id, name: t.name, teamLead: t.teamLead, members: updatedMembers)
            }
            for userId in memberIds {
                allQuarterAssignments.removeAll { $0.userId == userId && $0.weekStart == weekStart }
                if let project {
                    allQuarterAssignments.append((userId: userId, projectId: project.id, weekStart: weekStart))
                }
            }
            computeUncoveredWeeks()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - WeekPickerView

private struct WeekPickerView: View {
    let weeks: [Date]
    let selected: Date
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var currentWeekStart: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(weeks, id: \.self) { week in
                    Button {
                        onSelect(week)
                        dismiss()
                    } label: {
                        HStack {
                            Text(fmt.string(from: week))
                                .foregroundStyle(.primary)
                            Spacer()
                            if Calendar.current.isDate(week, inSameDayAs: currentWeekStart) {
                                Text("Current week")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if Calendar.current.isDate(week, inSameDayAs: selected) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - MemberAssignmentRow

private struct MemberAssignmentRow: View {
    let member: ScheduleMember
    let isLead: Bool
    let isMultiSelectMode: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if isMultiSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)
                }
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
                if !isMultiSelectMode {
                    Text(projectLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - ProjectPickerView

private struct ProjectPickerView: View {
    let member: ScheduleMember
    let projects: [ScheduleAssignedProject]
    let onSelect: (ScheduleAssignedProject?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var currentProjectId: Int? { member.assignments.first?.project.id }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None").foregroundStyle(.primary)
                        Spacer()
                        if currentProjectId == nil {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(projects) { project in
                    Button {
                        onSelect(project)
                        dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: project.color) ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(project.name).foregroundStyle(.primary)
                            Spacer()
                            if project.id == currentProjectId {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle(member.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - BulkProjectPickerView

private struct BulkProjectPickerView: View {
    let projects: [ScheduleAssignedProject]
    let onSelect: (ScheduleAssignedProject?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None").foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(projects) { project in
                    Button {
                        onSelect(project)
                        dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: project.color) ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(project.name).foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Assign Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - OnCallGapsView

private struct OnCallGapsView: View {
    let weeks: [Date]
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                ForEach(weeks, id: \.self) { week in
                    Button {
                        onSelect(week)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                            Text(fmt.string(from: week))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Missing On Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleDetailView(schedule: Schedule(id: 1, name: "Q1 2026", year: 2026, quarter: 1))
    }
    .environment(AuthManager())
}
