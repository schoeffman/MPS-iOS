//
//  EditUserView.swift
//  MPS-iOS
//

import SwiftUI

struct EditUserView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) private var dismiss

    let user: User
    let onSave: (User) -> Void

    @State private var fullName: String
    @State private var craftAbility: CraftAbility
    @State private var jobLevel: JobLevel
    @State private var craftFocus: CraftFocus
    @State private var levelStartDate: Date
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

    init(user: User, onSave: @escaping (User) -> Void) {
        self.user = user
        self.onSave = onSave
        _fullName = State(initialValue: user.fullName)
        _craftAbility = State(initialValue: CraftAbility(rawValue: user.craftAbility) ?? .Engineering)
        _jobLevel = State(initialValue: JobLevel(rawValue: user.jobLevel) ?? .Mid)
        _craftFocus = State(initialValue: CraftFocus(rawValue: user.craftFocus) ?? .NotApplicable)
        _levelStartDate = State(initialValue: {
            if let str = user.levelStartDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter.date(from: str) ?? Date()
            }
            return Date()
        }())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full Name", text: $fullName)
                }
                Section("Craft") {
                    Picker("Ability", selection: $craftAbility) {
                        ForEach(CraftAbility.allCases) { ability in
                            Text(ability.displayName).tag(ability)
                        }
                    }
                    Picker("Focus", selection: $craftFocus) {
                        ForEach(CraftFocus.allCases) { focus in
                            Text(focus.displayName).tag(focus)
                        }
                    }
                }
                Section("Level") {
                    Picker("Job Level", selection: $jobLevel) {
                        ForEach(JobLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    DatePicker(
                        "Start Date",
                        selection: $levelStartDate,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Edit User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(fullName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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

    private func save() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            struct Result: Decodable { let updateUser: User }
            let result: Result = try await client.fetch(
                query: """
                mutation UpdateUser($id: Int!, $input: UpdateUserInput!) {
                    updateUser(id: $id, input: $input) { id fullName craftAbility jobLevel craftFocus levelStartDate }
                }
                """,
                variables: [
                    "id": user.id,
                    "input": [
                        "fullName": fullName.trimmingCharacters(in: .whitespaces),
                        "craftAbility": craftAbility.rawValue,
                        "jobLevel": jobLevel.rawValue,
                        "craftFocus": craftFocus.rawValue,
                        "levelStartDate": levelStartDate.formatted(.iso8601.year().month().day()),
                    ]
                ],
                token: token
            )
            onSave(result.updateUser)
            dismiss()
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }
}
