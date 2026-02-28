//
//  WorkHistoryView.swift
//  MPS-iOS
//

import SwiftUI

struct WorkHistoryView: View {
    @Environment(AuthManager.self) var authManager

    @State private var startDate = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var endDate = Date()

    @State private var users: [WHUser] = []
    @State private var selectedUserId: Int? = nil

    @State private var results: [ProjectSummary] = []
    @State private var resultLabel = ""

    @State private var isLoadingUsers = false
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var error: String?

    private let client = GraphQLClient()
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                filtersSection
                resultsSection
            }
            .navigationTitle("Work History")
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

    // MARK: - Sections

    private var filtersSection: some View {
        Section("Filters") {
            DatePicker("Start Date", selection: $startDate, in: ...endDate, displayedComponents: .date)
            DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
            personPicker
            Button {
                Task { await search() }
            } label: {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Search")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(selectedUserId == nil || isSearching || isLoadingUsers)
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var personPicker: some View {
        if isLoadingUsers {
            HStack {
                Text("Person")
                Spacer()
                ProgressView()
            }
        } else {
            Picker("Person", selection: $selectedUserId) {
                Text("Select a person").tag(Optional<Int>.none)
                ForEach(users) { user in
                    Text(user.fullName).tag(Optional(user.id))
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if hasSearched {
            Section {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if results.isEmpty {
                    Text("No work history found for the selected person and date range.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { summary in
                        ProjectSummaryRow(summary: summary)
                    }
                }
            } header: {
                if !isSearching && !resultLabel.isEmpty {
                    Text(resultLabel)
                }
            }
        }
    }

    // MARK: - Data

    private func loadUsers() async {
        guard let token = authManager.sessionToken else { return }
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            struct Response: Decodable { let users: [WHUser] }
            let result: Response = try await client.fetch(
                query: "{ users { id fullName } }",
                token: token
            )
            users = result.users.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func search() async {
        guard let token = authManager.sessionToken,
              let userId = selectedUserId else { return }

        isSearching = true
        hasSearched = true
        defer { isSearching = false }

        let startStr = dateFmt.string(from: startDate)
        let endStr = dateFmt.string(from: endDate)

        do {
            // Step 1: get all dates in the range that have any work history data
            struct DatesResponse: Decodable { let workHistoryDates: [String] }
            let datesResult: DatesResponse = try await client.fetch(
                query: "query($s: String!, $e: String!) { workHistoryDates(startDate: $s, endDate: $e) }",
                variables: ["s": startStr, "e": endStr],
                token: token
            )

            let dates = datesResult.workHistoryDates
            guard !dates.isEmpty else {
                results = []
                buildResultLabel(userId: userId)
                return
            }

            // Step 2: fetch entries for all dates in a single aliased query
            let aliasParts = dates.enumerated().map { i, date in
                "d\(i): workHistory(date: \"\(date)\") { id user { id } project { id name color } }"
            }
            let combinedQuery = "{ \(aliasParts.joined(separator: " ")) }"
            let rawData = try await client.fetchRaw(query: combinedQuery, token: token)

            // Step 3: flatten, filter by user, tally by project
            var dayCounts: [Int: Int] = [:]          // projectId → day count
            var projectInfo: [Int: (name: String, color: String)] = [:]

            for (_, value) in rawData {
                guard
                    let arr = value as? [[String: Any]],
                    let encoded = try? JSONSerialization.data(withJSONObject: arr),
                    let entries = try? JSONDecoder().decode([WHRawEntry].self, from: encoded)
                else { continue }

                for entry in entries where entry.user.id == userId {
                    dayCounts[entry.project.id, default: 0] += 1
                    if projectInfo[entry.project.id] == nil {
                        projectInfo[entry.project.id] = (entry.project.name, entry.project.color)
                    }
                }
            }

            results = dayCounts
                .compactMap { id, count -> ProjectSummary? in
                    guard let info = projectInfo[id] else { return nil }
                    return ProjectSummary(id: id, name: info.name, color: info.color, dayCount: count)
                }
                .sorted { $0.dayCount > $1.dayCount }

            buildResultLabel(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func buildResultLabel(userId: Int) {
        let name = users.first { $0.id == userId }?.fullName ?? ""
        let start = displayFmt.string(from: startDate)
        let end = displayFmt.string(from: endDate)
        resultLabel = "\(name)  ·  \(start) – \(end)"
    }

    // MARK: - Models

    fileprivate struct WHUser: Identifiable, Decodable {
        let id: Int
        let fullName: String
    }

    fileprivate struct ProjectSummary: Identifiable {
        let id: Int
        let name: String
        let color: String
        let dayCount: Int
    }

    private struct WHRawEntry: Decodable {
        struct WHRawUser: Decodable { let id: Int }
        struct WHRawProject: Decodable { let id: Int; let name: String; let color: String }
        let id: Int
        let user: WHRawUser
        let project: WHRawProject
    }
}

// MARK: - Supporting Views

private struct ProjectSummaryRow: View {
    let summary: WorkHistoryView.ProjectSummary

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: summary.color) ?? Color.accentColor)
                .frame(width: 12, height: 12)
            Text(summary.name)
            Spacer()
            Text("\(summary.dayCount) day\(summary.dayCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    WorkHistoryView()
        .environment(AuthManager())
}
