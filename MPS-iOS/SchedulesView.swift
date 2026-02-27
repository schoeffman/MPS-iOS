//
//  SchedulesView.swift
//  MPS-iOS
//

import SwiftUI

struct SchedulesView: View {
    @Environment(AuthManager.self) var authManager

    @State private var schedules: [Schedule] = []
    @State private var isLoading = false
    @State private var error: String?

    private let client = GraphQLClient()

    // Server already returns newest first (year desc, quarter desc)
    private var sorted: [Schedule] {
        schedules.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.quarter > $1.quarter
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedules")
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
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sorted.isEmpty {
            ContentUnavailableView(
                "No Schedules",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No schedules found in this space.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(sorted) { schedule in
                ScheduleRow(schedule: schedule)
            }
            .listStyle(.plain)
        }
    }

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Response: Decodable { let schedules: [Schedule] }
            let result: Response = try await client.fetch(
                query: "{ schedules { id name year quarter } }",
                token: token
            )
            schedules = result.schedules
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - ScheduleRow

private struct ScheduleRow: View {
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(schedule.name)
                .font(.body.weight(.medium))
            Text("Q\(schedule.quarter) · \(schedule.year)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SchedulesView()
        .environment(AuthManager())
}
