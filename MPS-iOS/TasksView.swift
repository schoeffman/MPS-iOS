//
//  TasksView.swift
//  MPS-iOS
//

import SwiftUI

struct TasksView: View {
    var body: some View {
        NavigationStack {
            Text("")
                .navigationTitle("Tasks")
        }
    }
}

#Preview {
    TasksView()
        .environment(AuthManager())
}
