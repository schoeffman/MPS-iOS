//
//  UserDetailView.swift
//  MPS-iOS
//

import SwiftUI

struct UserDetailView: View {
    @Environment(AuthManager.self) var authManager
    @State private var currentUser: User
    @State private var showEdit = false

    init(user: User) {
        _currentUser = State(initialValue: user)
    }

    var body: some View {
        List {
            Section("Craft") {
                LabeledContent("Ability", value: currentUser.craftAbility.displayName)
                LabeledContent("Focus") {
                    Text(currentUser.craftFocus == "NotApplicable" ? "N/A" : currentUser.craftFocus)
                }
            }
            Section("Level") {
                LabeledContent("Job Level", value: currentUser.jobLevel)
                if let dateStr = currentUser.levelStartDate, let date = parseDate(dateStr) {
                    LabeledContent("Start Date", value: date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .navigationTitle(currentUser.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditUserView(user: currentUser) { updated in
                currentUser = updated
            }
            .environment(authManager)
        }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }
}

private extension String {
    var displayName: String {
        switch self {
        case "ProductManagement": return "Product Management"
        case "DataScience": return "Data Science"
        default: return self
        }
    }
}
