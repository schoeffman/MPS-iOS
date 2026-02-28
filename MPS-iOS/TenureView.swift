//
//  TenureView.swift
//  MPS-iOS
//

import SwiftUI

struct TenureView: View {
    var embedded = false

    @Environment(AuthManager.self) var authManager

    @State private var users: [User] = []
    @State private var limits: [LevelLimit] = []
    @State private var isLoading = false
    @State private var error: String?

    private let client = GraphQLClient()
    private let levelOrder = ["Junior", "Mid", "Senior", "Staff", "Principal"]

    // MARK: - Computed

    private var limitMap: [String: Int] {
        Dictionary(uniqueKeysWithValues: limits.map { ($0.jobLevel, $0.limitMonths) })
    }

    private var noLimitsConfigured: Bool {
        limits.allSatisfy { $0.limitMonths == 0 }
    }

    private var trackedGroups: [TrackedGroup] {
        levelOrder.compactMap { level in
            let limit = limitMap[level] ?? 0
            guard limit > 0 else { return nil }
            let levelUsers = users
                .filter { $0.jobLevel == level }
                .sorted { a, b in
                    let ra = tenureRemaining(a.levelStartDate, limit: limit)
                    let rb = tenureRemaining(b.levelStartDate, limit: limit)
                    switch (ra, rb) {
                    case (nil, nil): return a.fullName.localizedCaseInsensitiveCompare(b.fullName) == .orderedAscending
                    case (nil, _):  return false
                    case (_, nil):  return true
                    case (let ra?, let rb?): return ra < rb
                    }
                }
            guard !levelUsers.isEmpty else { return nil }
            return TrackedGroup(level: level, limitMonths: limit, users: levelUsers)
        }
    }

    private var untrackedGroups: [(level: String, users: [User])] {
        let trackedLevelSet = Set(trackedGroups.map { $0.level })
        let untrackedStandard = levelOrder.filter { level in
            !trackedLevelSet.contains(level) && (limitMap[level] ?? 0) == 0
        }
        let knownLevels = Set(levelOrder)
        let extraLevels = Set(users.map { $0.jobLevel })
            .subtracting(knownLevels)
            .sorted()

        var groups: [(level: String, users: [User])] = []
        for level in untrackedStandard + extraLevels {
            let levelUsers = users
                .filter { $0.jobLevel == level }
                .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
            if !levelUsers.isEmpty { groups.append((level, levelUsers)) }
        }
        return groups
    }

    // MARK: - Body

    var body: some View {
        if embedded {
            tenureContent
        } else {
            NavigationStack { tenureContent }
        }
    }

    private var tenureContent: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if noLimitsConfigured {
                noLimitsView
            } else if trackedGroups.isEmpty && untrackedGroups.isEmpty {
                ContentUnavailableView(
                    "No Users",
                    systemImage: "person.slash",
                    description: Text("No users found in this space.")
                )
            } else {
                tenureList
            }
        }
        .navigationTitle("Tenure")
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

    // MARK: - Subviews

    private var noLimitsView: some View {
        ContentUnavailableView(
            "No Limits Configured",
            systemImage: "timer",
            description: Text("Set time-in-level limits in Space Settings to track tenure progress.")
        )
    }

    private var tenureList: some View {
        List {
            trackedSections
            untrackedSections
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var trackedSections: some View {
        ForEach(trackedGroups, id: \.level) { group in
            Section {
                ForEach(group.users) { user in
                    NavigationLink(destination: UserDetailView(user: user)) {
                        TenureUserRow(user: user, limitMonths: group.limitMonths)
                    }
                }
            } header: {
                HStack {
                    Text(group.level)
                    Spacer()
                    Text("\(group.limitMonths) months")
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var untrackedSections: some View {
        if !untrackedGroups.isEmpty {
            ForEach(untrackedGroups, id: \.level) { group in
                Section {
                    ForEach(group.users) { user in
                        NavigationLink(destination: UserDetailView(user: user)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.fullName)
                                    .font(.body.weight(.medium))
                                Text(tenureFormatDate(user.levelStartDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.level)
                        Spacer()
                        Text("No limit")
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
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
            struct LoadResponse: Decodable {
                let users: [User]
                let jobLevelLimits: [LevelLimit]
            }
            let result: LoadResponse = try await client.fetch(
                query: "{ users { id fullName craftAbility jobLevel craftFocus levelStartDate } jobLevelLimits { jobLevel limitMonths } }",
                token: token
            )
            users = result.users
            limits = result.jobLevelLimits
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Models

    private struct LevelLimit: Decodable {
        let jobLevel: String
        let limitMonths: Int
    }

    fileprivate struct TrackedGroup {
        let level: String
        let limitMonths: Int
        let users: [User]
    }
}

// MARK: - Tenure Row

private struct TenureUserRow: View {
    let user: User
    let limitMonths: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(user.fullName)
                    .font(.body.weight(.medium))
                Spacer()
                remainingBadge
            }
            Text(tenureFormatDate(user.levelStartDate))
                .font(.caption)
                .foregroundStyle(.secondary)
            TenureProgressBar(progress: progress, color: statusColor)
        }
        .padding(.vertical, 4)
    }

    private var elapsed: Int? {
        tenureMonthsElapsed(from: user.levelStartDate)
    }

    private var remaining: Int? {
        elapsed.map { limitMonths - $0 }
    }

    private var progress: Double {
        guard let e = elapsed, limitMonths > 0 else { return 0 }
        return Double(e) / Double(limitMonths)
    }

    private var statusColor: Color {
        guard let r = remaining else { return Color(.systemGray4) }
        if r < 0  { return .red }
        if r <= 12 { return .orange }
        return .green
    }

    private var remainingBadge: some View {
        let (text, color) = badgeInfo
        return Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var badgeInfo: (String, Color) {
        guard let r = remaining else {
            return ("No start date", Color.secondary)
        }
        if r < 0  { return ("\(abs(r)) mo over", .red) }
        if r == 0 { return ("At limit", .red) }
        if r <= 12 { return ("\(r) mo left", .orange) }
        return ("\(r) mo left", .green)
    }
}

// MARK: - Progress Bar

private struct TenureProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Helpers

private func tenureMonthsElapsed(from dateStr: String?) -> Int? {
    guard let dateStr else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let date = fmt.date(from: dateStr) else { return nil }
    return Calendar.current.dateComponents([.month], from: date, to: Date()).month
}

private func tenureRemaining(_ dateStr: String?, limit: Int) -> Int? {
    tenureMonthsElapsed(from: dateStr).map { limit - $0 }
}

private func tenureFormatDate(_ dateStr: String?) -> String {
    guard let dateStr else { return "Not set" }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let date = fmt.date(from: dateStr) else { return "Not set" }
    let display = DateFormatter()
    display.dateFormat = "MMMM yyyy"
    return display.string(from: date)
}

// MARK: - Preview

#Preview {
    TenureView()
        .environment(AuthManager())
}
