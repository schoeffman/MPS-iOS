//
//  CreateUserView.swift
//  MPS-iOS
//

import SwiftUI

struct CreateUserView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var craftAbility = CraftAbility.Engineering
    @State private var jobLevel = JobLevel.Mid
    @State private var craftFocus = CraftFocus.NotApplicable
    @State private var levelStartDate = Date()
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

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
            .navigationTitle("New User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await save() } }
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
            struct Result: Decodable { let createUser: User }
            let _: Result = try await client.fetch(
                query: """
                mutation CreateUser($input: CreateUserInput!) {
                    createUser(input: $input) { id fullName craftAbility jobLevel craftFocus }
                }
                """,
                variables: [
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
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    CreateUserView()
        .environment(AuthManager())
}
