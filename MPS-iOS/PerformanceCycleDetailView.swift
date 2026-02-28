//
//  PerformanceCycleDetailView.swift
//  MPS-iOS
//

import SwiftUI

// MARK: - Rating & Trend Definitions

private struct RatingDef: Identifiable {
    let id: String        // raw server value, or "__unrated__" for nil
    let value: String?    // actual server value (nil = unrated)
    let label: String
    let shortLabel: String
    let color: Color
}

private let ratingDefs: [RatingDef] = [
    RatingDef(id: "__unrated__",            value: nil,                         label: "Unrated",               shortLabel: "Unrated",     color: Color(.systemGray3)),
    RatingDef(id: "GreatlyExceeding",       value: "GreatlyExceeding",          label: "Greatly Exceeding",     shortLabel: "Greatly Exc", color: .purple),
    RatingDef(id: "Exceeding",              value: "Exceeding",                 label: "Exceeding",             shortLabel: "Exceeding",   color: .green),
    RatingDef(id: "MetExpectations",        value: "MetExpectations",           label: "Met Expectations",      shortLabel: "Met Exp.",    color: .blue),
    RatingDef(id: "MetMostExpectations",    value: "MetMostExpectations",       label: "Met Most Expectations", shortLabel: "Met Most",    color: .orange),
    RatingDef(id: "DidNotMeetExpectations", value: "DidNotMeetExpectations",    label: "Did Not Meet",          shortLabel: "Did Not Meet",color: .red),
    RatingDef(id: "NotEligible",            value: "NotEligible",               label: "Not Eligible",          shortLabel: "Not Eligible",color: Color(.systemGray)),
]

private let trendDefs: [(value: String?, symbol: String, color: Color)] = [
    (nil, "—", Color(.systemGray3)),
    ("+", "+", .green),
    ("=", "=", .blue),
    ("-", "−", .red),
]

private func ratingDef(for value: String?) -> RatingDef {
    ratingDefs.first { $0.value == value } ?? ratingDefs[0]
}

// MARK: - Detail View

struct PerformanceCycleDetailView: View {
    let cycleId: Int
    let title: String

    @Environment(AuthManager.self) var authManager

    @State private var cycleTitle = ""
    @State private var cycleMonth = ""
    @State private var members: [PCDetailUser] = []
    @State private var limitMap: [String: Int] = [:]
    @State private var isLoading = false
    @State private var savedUserId: Int? = nil
    @State private var historyUser: PCDetailUser? = nil
    @State private var error: String?

    private let client = GraphQLClient()

    var body: some View {
        Group {
            if isLoading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailList
            }
        }
        .navigationTitle(cycleTitle.isEmpty ? title : cycleTitle)
        .task { await load() }
        .sheet(item: $historyUser) { user in
            UserCycleHistorySheet(userId: user.id, userName: user.fullName)
                .environment(authManager)
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

    // MARK: - Subviews

    private var detailList: some View {
        List {
            if !cycleMonth.isEmpty {
                Section {
                    RatingDistributionBar(members: members)
                } header: {
                    Text(pcDetailFormatMonth(cycleMonth))
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Members (\(members.count))") {
                ForEach($members) { $member in
                    PCMemberRow(
                        member: $member,
                        limitMonths: limitMap[member.jobLevel],
                        cycleId: cycleId,
                        onShowHistory: { historyUser = member },
                        onSaved: { showSaved(for: member.id) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) {
            if savedUserId != nil {
                Text("Saved")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: savedUserId != nil)
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct LimitRow: Decodable { let jobLevel: String; let limitMonths: Int }
            struct Resp: Decodable {
                let performanceCycle: PCDetailCycle?
                let jobLevelLimits: [LimitRow]
            }
            let result: Resp = try await client.fetch(
                query: """
                query($id: Int!) {
                    performanceCycle(id: $id) {
                        id title cycleMonth
                        users { id fullName jobLevel levelStartDate rating trend }
                    }
                    jobLevelLimits { jobLevel limitMonths }
                }
                """,
                variables: ["id": cycleId],
                token: token
            )
            if let cycle = result.performanceCycle {
                cycleTitle = cycle.title
                cycleMonth = cycle.cycleMonth
                members = cycle.users
            }
            limitMap = Dictionary(
                uniqueKeysWithValues: result.jobLevelLimits
                    .filter { $0.limitMonths > 0 }
                    .map { ($0.jobLevel, $0.limitMonths) }
            )
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }

    private func showSaved(for userId: Int) {
        savedUserId = userId
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            savedUserId = nil
        }
    }
}

// MARK: - Rating Distribution Bar

private struct RatingDistributionBar: View {
    let members: [PCDetailUser]

    private var counts: [String: Int] {
        var c: [String: Int] = [:]
        for m in members {
            c[m.rating ?? "__unrated__", default: 0] += 1
        }
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(ratingDefs) { def in
                        let count = counts[def.id] ?? 0
                        if count > 0 {
                            Rectangle()
                                .fill(def.color)
                                .frame(width: geo.size.width * Double(count) / Double(max(members.count, 1)))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 18)

            legendGrid
        }
        .padding(.vertical, 4)
    }

    private var legendGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        let active = ratingDefs.filter { (counts[$0.id] ?? 0) > 0 }
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(active) { def in
                HStack(spacing: 5) {
                    Circle().fill(def.color).frame(width: 8, height: 8)
                    Text("\(def.shortLabel)  \(counts[def.id] ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Member Row

private struct PCMemberRow: View {
    @Binding var member: PCDetailUser
    let limitMonths: Int?
    let cycleId: Int
    let onShowHistory: () -> Void
    let onSaved: () -> Void

    @Environment(AuthManager.self) var authManager
    private let client = GraphQLClient()

    private var elapsed: Int? { pcMonthsElapsed(from: member.levelStartDate) }
    private var remaining: Int? { elapsed.map { (limitMonths ?? 0) - $0 } }
    private var progress: Double {
        guard let e = elapsed, let limit = limitMonths, limit > 0 else { return 0 }
        return Double(e) / Double(limit)
    }
    private var progressColor: Color {
        guard let r = remaining else { return Color(.systemGray4) }
        if r < 0 { return .red }
        if r <= 12 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            nameRow
            levelRow
            if limitMonths != nil && elapsed != nil {
                PCProgressBar(progress: progress, color: progressColor)
            }
            ratingRow
        }
        .padding(.vertical, 4)
    }

    private var nameRow: some View {
        HStack {
            Button(action: onShowHistory) {
                HStack(spacing: 4) {
                    Text(member.fullName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            trendMenu
        }
    }

    private var levelRow: some View {
        HStack(spacing: 8) {
            Text(member.jobLevel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let r = remaining, limitMonths != nil {
                let (text, color) = remainingBadgeInfo(r)
                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var ratingRow: some View {
        let def = ratingDef(for: member.rating)
        return Menu {
            ForEach(ratingDefs) { r in
                Button {
                    Task { await setRating(r.value) }
                } label: {
                    Label(r.label, systemImage: member.rating == r.value ? "checkmark" : "")
                }
            }
        } label: {
            HStack {
                Circle().fill(def.color).frame(width: 8, height: 8)
                Text(def.label)
                    .font(.subheadline)
                    .foregroundStyle(def.color)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(def.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var trendMenu: some View {
        let current = trendDefs.first { $0.value == member.trend } ?? trendDefs[0]
        return Menu {
            ForEach(trendDefs, id: \.symbol) { t in
                Button {
                    Task { await setTrend(t.value) }
                } label: {
                    Label(t.symbol, systemImage: member.trend == t.value ? "checkmark" : "")
                }
            }
        } label: {
            Text(current.symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(current.color)
                .frame(minWidth: 28)
        }
    }

    private func remainingBadgeInfo(_ remaining: Int) -> (String, Color) {
        if remaining < 0  { return ("\(abs(remaining)) mo over", .red) }
        if remaining == 0 { return ("At limit", .red) }
        if remaining <= 12 { return ("\(remaining) mo left", .orange) }
        return ("\(remaining) mo left", .green)
    }

    private func setRating(_ rating: String?) async {
        guard let token = authManager.sessionToken else { return }
        let prev = member.rating
        member.rating = rating
        do {
            struct Resp: Decodable { let setPerformanceCycleMemberRating: Bool }
            var vars: [String: Any] = ["cycleId": cycleId, "userId": member.id]
            if let r = rating { vars["rating"] = r } else { vars["rating"] = NSNull() }
            let _: Resp = try await client.fetch(
                query: "mutation($cycleId: Int!, $userId: Int!, $rating: String) { setPerformanceCycleMemberRating(cycleId: $cycleId, userId: $userId, rating: $rating) }",
                variables: vars,
                token: token
            )
            onSaved()
        } catch {
            member.rating = prev
        }
    }

    private func setTrend(_ trend: String?) async {
        guard let token = authManager.sessionToken else { return }
        let prev = member.trend
        member.trend = trend
        do {
            struct Resp: Decodable { let setPerformanceCycleMemberTrend: Bool }
            var vars: [String: Any] = ["cycleId": cycleId, "userId": member.id]
            if let t = trend { vars["trend"] = t } else { vars["trend"] = NSNull() }
            let _: Resp = try await client.fetch(
                query: "mutation($cycleId: Int!, $userId: Int!, $trend: String) { setPerformanceCycleMemberTrend(cycleId: $cycleId, userId: $userId, trend: $trend) }",
                variables: vars,
                token: token
            )
            onSaved()
        } catch {
            member.trend = prev
        }
    }
}

// MARK: - Progress Bar

private struct PCProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - User History Sheet

private struct UserCycleHistorySheet: View {
    let userId: Int
    let userName: String

    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss

    @State private var history: [HistoryEntry] = []
    @State private var isLoading = false

    private let client = GraphQLClient()

    struct HistoryEntry: Decodable {
        let cycleId: Int
        let cycleTitle: String
        let cycleMonth: String
        let rating: String?
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if history.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("\(userName) has not been included in any cycles yet.")
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("\(userName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var historyList: some View {
        List(history, id: \.cycleId) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.cycleTitle).font(.body.weight(.medium))
                    Text(pcDetailFormatMonth(entry.cycleMonth))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let def = ratingDef(for: entry.rating)
                HStack(spacing: 5) {
                    Circle().fill(def.color).frame(width: 8, height: 8)
                    Text(def.shortLabel)
                        .font(.subheadline)
                        .foregroundStyle(def.color)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Resp: Decodable { let userPerformanceCycles: [HistoryEntry] }
            let result: Resp = try await client.fetch(
                query: "query($userId: Int!) { userPerformanceCycles(userId: $userId) { cycleId cycleTitle cycleMonth rating } }",
                variables: ["userId": userId],
                token: token
            )
            history = result.userPerformanceCycles
        } catch {}
    }
}

// MARK: - Models

struct PCDetailUser: Identifiable, Decodable {
    let id: Int
    let fullName: String
    let jobLevel: String
    let levelStartDate: String?
    var rating: String?
    var trend: String?
}

private struct PCDetailCycle: Decodable {
    let id: Int
    let title: String
    let cycleMonth: String
    let users: [PCDetailUser]
}

// MARK: - Helpers

private func pcMonthsElapsed(from dateStr: String?) -> Int? {
    guard let dateStr else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let date = fmt.date(from: dateStr) else { return nil }
    return Calendar.current.dateComponents([.month], from: date, to: Date()).month
}

private func pcDetailFormatMonth(_ cycleMonth: String) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM"
    guard let date = fmt.date(from: cycleMonth) else { return cycleMonth }
    let display = DateFormatter()
    display.dateFormat = "MMMM yyyy"
    return display.string(from: date)
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PerformanceCycleDetailView(cycleId: 1, title: "Q1 2026")
    }
    .environment(AuthManager())
}
