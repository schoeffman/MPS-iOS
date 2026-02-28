//
//  EditScheduleView.swift
//  MPS-iOS
//

import SwiftUI

struct EditScheduleView: View {
    let schedule: Schedule
    let onSave: (Schedule) -> Void

    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var year: Int
    @State private var quarter: Int
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

    private let currentYear = Calendar.current.component(.year, from: Date())

    private var years: [Int] {
        let base = currentYear
        return Array((base - 1)...(base + 3))
    }

    init(schedule: Schedule, onSave: @escaping (Schedule) -> Void) {
        self.schedule = schedule
        self.onSave = onSave
        _name = State(initialValue: schedule.name)
        _year = State(initialValue: schedule.year)
        _quarter = State(initialValue: schedule.quarter)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                scheduleSection
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
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
    }

    private var nameSection: some View {
        Section {
            TextField("Schedule Name", text: $name)
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Year", selection: $year) {
                ForEach(years, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            Picker("Quarter", selection: $quarter) {
                Text("Q1").tag(1)
                Text("Q2").tag(2)
                Text("Q3").tag(3)
                Text("Q4").tag(4)
            }
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

    private func save() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            struct Result: Decodable { let updateSchedule: Schedule }
            let result: Result = try await client.fetch(
                query: """
                mutation UpdateSchedule($id: Int!, $input: UpdateScheduleInput!) {
                    updateSchedule(id: $id, input: $input) { id name year quarter }
                }
                """,
                variables: [
                    "id": schedule.id,
                    "input": [
                        "name": name.trimmingCharacters(in: .whitespaces),
                        "year": year,
                        "quarter": quarter
                    ]
                ],
                token: token
            )
            onSave(result.updateSchedule)
            dismiss()
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }
}
