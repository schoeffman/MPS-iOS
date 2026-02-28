//
//  DashboardView.swift
//  MPS-iOS
//

import SwiftUI

struct DashboardView: View {
    @Environment(AuthManager.self) var authManager

    @State private var onCallAssignments:   [DashOnCallAssignment]   = []
    @State private var leaveAssignments:    [DashLeaveAssignment]    = []
    @State private var scheduledProjects:   [DashScheduledProject]   = []
    @State private var unscheduledProjects: [DashUnscheduledProject] = []
    @State private var isLoading = true
    @State private var error: String?

    private let client = GraphQLClient()

    // MARK: - Dates (computed fresh on each render to be accurate)

    private var monday: Date { dashMonday() }
    private var nextMonday: Date { Calendar.current.date(byAdding: .day, value: 7, to: monday)! }
    private var mondayStr: String { dashFmtDate(monday) }
    private var nextMondayStr: String { dashFmtDate(nextMonday) }
    private var endStr: String { dashFmtDate(Calendar.current.date(byAdding: .day, value: 31, to: monday)!) }

    // MARK: - Body

    var body: some View {
        NavigationStack { dashContent }
    }

    private var dashContent: some View {
        Group {
            if isLoading && onCallAssignments.isEmpty && leaveAssignments.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollContent
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
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

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                onCallThisWeekCard
                onCallNextWeekCard
                leaveThisWeekCard
                upcomingLeaveCard
                scheduledProjectsCard
                unscheduledProjectsCard
            }
            .padding()
        }
        .refreshable { await load() }
    }

    // MARK: - On Call

    private var thisWeekOnCall: [String] {
        onCallAssignments.filter { $0.weekStart == mondayStr }.map { $0.userName }
    }

    private var nextWeekOnCall: [String] {
        onCallAssignments.filter { $0.weekStart == nextMondayStr }.map { $0.userName }
    }

    private var onCallThisWeekCard: some View {
        DashCard(title: "On Call This Week") {
            if thisWeekOnCall.isEmpty {
                DashEmptyRow(text: "No one is on call this week.")
            } else {
                ForEach(thisWeekOnCall, id: \.self) { name in
                    DashNameRow(name: name)
                }
            }
        }
    }

    private var onCallNextWeekCard: some View {
        DashCard(title: "On Call Next Week") {
            if nextWeekOnCall.isEmpty {
                DashEmptyRow(text: "No one is on call next week.")
            } else {
                ForEach(nextWeekOnCall, id: \.self) { name in
                    DashNameRow(name: name)
                }
            }
        }
    }

    // MARK: - Leave

    private var thisWeekLeave: [DashLeaveEntry] {
        let fromAssignments = leaveAssignments
            .filter { $0.weekStart == mondayStr }
            .map { DashLeaveEntry(userName: $0.userName, leaveName: $0.projectName) }
        let fromHolidays = dashHolidaysInWeek(monday)
            .map { DashLeaveEntry(userName: "US Teams", leaveName: $0) }
        return fromAssignments + fromHolidays
    }

    private var upcomingLeaveWeeks: [DashWeekLeave] {
        var result: [DashWeekLeave] = []
        var date = nextMonday
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 31, to: monday)!
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        while date <= end {
            let str = dashFmtDate(date)
            let fromAssignments = leaveAssignments
                .filter { $0.weekStart == str }
                .map { DashLeaveEntry(userName: $0.userName, leaveName: $0.projectName) }
            let fromHolidays = dashHolidaysInWeek(date)
                .map { DashLeaveEntry(userName: "US Teams", leaveName: $0) }
            let entries = fromAssignments + fromHolidays
            if !entries.isEmpty {
                result.append(DashWeekLeave(id: str, label: fmt.string(from: date), entries: entries))
            }
            date = cal.date(byAdding: .day, value: 7, to: date)!
        }
        return result
    }

    private var leaveThisWeekCard: some View {
        DashCard(title: "On Leave This Week") {
            if thisWeekLeave.isEmpty {
                DashEmptyRow(text: "No one is on leave this week.")
            } else {
                ForEach(thisWeekLeave) { entry in
                    DashLeaveRow(entry: entry)
                }
            }
        }
    }

    private var upcomingLeaveCard: some View {
        DashCard(title: "Upcoming Leave") {
            if upcomingLeaveWeeks.isEmpty {
                DashEmptyRow(text: "No upcoming leave in the next 31 days.")
            } else {
                ForEach(upcomingLeaveWeeks) { week in
                    upcomingWeekSection(week)
                }
            }
        }
    }

    private func upcomingWeekSection(_ week: DashWeekLeave) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(week.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(week.entries) { entry in
                DashLeaveRow(entry: entry)
            }
        }
    }

    // MARK: - Projects

    private var scheduledProjectsCard: some View {
        DashCard(title: "Projects Scheduled This Week") {
            if scheduledProjects.isEmpty {
                DashEmptyRow(text: "No projects scheduled this week.")
            } else {
                ForEach(scheduledProjects) { project in
                    DashScheduledRow(project: project)
                }
            }
        }
    }

    private var unscheduledProjectsCard: some View {
        DashCard(title: "Projects Not Scheduled This Week") {
            if unscheduledProjects.isEmpty {
                DashEmptyRow(text: "All active projects are scheduled this week.")
            } else {
                ForEach(unscheduledProjects) { project in
                    DashUnscheduledRow(project: project)
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Resp: Decodable {
                let leaveAssignments: [DashLeaveAssignment]
                let onCallAssignments: [DashOnCallAssignment]
                let scheduledProjects: [DashScheduledProject]
                let unscheduledProjects: [DashUnscheduledProject]
            }
            let result: Resp = try await client.fetch(
                query: """
                query($startDate: String!, $endDate: String!, $weekStart: String!) {
                    leaveAssignments(startDate: $startDate, endDate: $endDate) {
                        userId userName projectName weekStart
                    }
                    onCallAssignments(startDate: $startDate, endDate: $endDate) {
                        userId userName weekStart
                    }
                    scheduledProjects(weekStart: $weekStart) {
                        projectId projectName color status assignees targetDate
                    }
                    unscheduledProjects(weekStart: $weekStart) {
                        projectId projectName color status targetDate
                    }
                }
                """,
                variables: [
                    "startDate": mondayStr,
                    "endDate": endStr,
                    "weekStart": mondayStr
                ],
                token: token
            )
            leaveAssignments    = result.leaveAssignments
            onCallAssignments   = result.onCallAssignments
            scheduledProjects   = result.scheduledProjects
            unscheduledProjects = result.unscheduledProjects
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Card Container

private struct DashCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Row Views

private struct DashNameRow: View {
    let name: String
    var body: some View {
        Text(name)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}

private struct DashLeaveRow: View {
    let entry: DashLeaveEntry
    var body: some View {
        HStack {
            Text(entry.userName)
            Spacer()
            Text(entry.leaveName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct DashScheduledRow: View {
    let project: DashScheduledProject
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: project.color) ?? Color.accentColor)
                    .frame(width: 10, height: 10)
                Text(project.projectName)
                    .font(.body.weight(.medium))
                Spacer()
                DashStatusBadge(status: project.status)
            }
            if !project.assignees.isEmpty {
                Text(project.assignees.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct DashUnscheduledRow: View {
    let project: DashUnscheduledProject
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: project.color) ?? Color.accentColor)
                .frame(width: 10, height: 10)
            Text(project.projectName)
                .font(.body.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                DashStatusBadge(status: project.status)
                if let d = project.targetDate, !d.isEmpty {
                    Text(dashFmtDisplayDate(d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct DashStatusBadge: View {
    let status: String

    private var color: Color {
        switch status {
        case "Complete":  return .green
        case "Explore":   return .blue
        case "Make":      return .purple
        case "Paused":    return .orange
        case "Cancelled": return .red
        default:          return Color.secondary
        }
    }

    var body: some View {
        Text(status)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct DashEmptyRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

// MARK: - Models

fileprivate struct DashOnCallAssignment: Decodable {
    let userId: Int
    let userName: String
    let weekStart: String
}

fileprivate struct DashLeaveAssignment: Decodable {
    let userId: Int
    let userName: String
    let projectName: String
    let weekStart: String
}

fileprivate struct DashScheduledProject: Identifiable, Decodable {
    let projectId: Int
    let projectName: String
    let color: String
    let status: String
    let assignees: [String]
    let targetDate: String?
    var id: Int { projectId }
}

fileprivate struct DashUnscheduledProject: Identifiable, Decodable {
    let projectId: Int
    let projectName: String
    let color: String
    let status: String
    let targetDate: String?
    var id: Int { projectId }
}

fileprivate struct DashLeaveEntry: Identifiable {
    let id = UUID()
    let userName: String
    let leaveName: String
}

fileprivate struct DashWeekLeave: Identifiable {
    let id: String
    let label: String
    let entries: [DashLeaveEntry]
}

// MARK: - Date Helpers

fileprivate func dashMonday() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    return cal.date(from: comps) ?? Date()
}

fileprivate func dashFmtDate(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    return fmt.string(from: date)
}

fileprivate func dashFmtDisplayDate(_ dateStr: String) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let date = fmt.date(from: dateStr) else { return dateStr }
    let display = DateFormatter()
    display.dateFormat = "MMM d, yyyy"
    return display.string(from: date)
}

// MARK: - Holiday Helpers (ported from schedule-utils.ts)

// month: 0-based (Jan=0), weekday: 0=Sun,1=Mon,...,6=Sat
fileprivate func dashNthWeekday(year: Int, month: Int, weekday: Int, n: Int) -> Date {
    let cal = Calendar(identifier: .gregorian)
    let first = cal.date(from: DateComponents(year: year, month: month + 1, day: 1))!
    let firstWD = cal.component(.weekday, from: first) - 1
    let offset = (weekday - firstWD + 7) % 7
    let day = 1 + offset + (n - 1) * 7
    return cal.date(from: DateComponents(year: year, month: month + 1, day: day))!
}

// month: 0-based, weekday: 0=Sun,...,6=Sat
fileprivate func dashLastWeekday(year: Int, month: Int, weekday: Int) -> Date {
    let cal = Calendar(identifier: .gregorian)
    let firstOfNext = cal.date(from: DateComponents(year: year, month: month + 2, day: 1))!
    let lastDay = cal.date(byAdding: .day, value: -1, to: firstOfNext)!
    let lastWD = cal.component(.weekday, from: lastDay) - 1
    let diff = (lastWD - weekday + 7) % 7
    return cal.date(byAdding: .day, value: -diff, to: lastDay)!
}

fileprivate func dashObserved(_ date: Date) -> Date {
    let cal = Calendar(identifier: .gregorian)
    let wd = cal.component(.weekday, from: date) - 1  // 0=Sun,...,6=Sat
    if wd == 6 { return cal.date(byAdding: .day, value: -1, to: date)! }  // Sat → Fri
    if wd == 0 { return cal.date(byAdding: .day, value:  1, to: date)! }  // Sun → Mon
    return date
}

fileprivate func dashUSHolidays(year: Int) -> [(date: Date, name: String)] {
    let cal = Calendar(identifier: .gregorian)
    func fixed(_ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: m, day: d))!
    }
    return [
        (dashObserved(fixed(1, 1)),                                "New Year's Day"),
        (dashNthWeekday(year: year, month: 0, weekday: 1, n: 3),  "MLK Day"),
        (dashNthWeekday(year: year, month: 1, weekday: 1, n: 3),  "Presidents' Day"),
        (dashLastWeekday(year: year, month: 4, weekday: 1),        "Memorial Day"),
        (dashObserved(fixed(6, 19)),                               "Juneteenth"),
        (dashObserved(fixed(7, 4)),                                "Independence Day"),
        (dashNthWeekday(year: year, month: 8, weekday: 1, n: 1),  "Labor Day"),
        (dashNthWeekday(year: year, month: 9, weekday: 1, n: 2),  "Columbus Day"),
        (dashObserved(fixed(11, 11)),                              "Veterans Day"),
        (dashNthWeekday(year: year, month: 10, weekday: 4, n: 4), "Thanksgiving"),
        (dashObserved(fixed(12, 25)),                              "Christmas Day"),
    ]
}

fileprivate func dashHolidaysInWeek(_ weekStart: Date) -> [String] {
    let cal = Calendar(identifier: .gregorian)
    let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
    let y1 = cal.component(.year, from: weekStart)
    let y2 = cal.component(.year, from: weekEnd)
    var holidays = dashUSHolidays(year: y1)
    if y2 != y1 { holidays += dashUSHolidays(year: y2) }
    return holidays.filter { $0.date >= weekStart && $0.date <= weekEnd }.map { $0.name }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environment(AuthManager())
}
