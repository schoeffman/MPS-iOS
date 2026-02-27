//
//  DashboardView.swift
//  MPS-iOS
//

import SwiftUI

struct DashboardView: View {
    @Environment(AuthManager.self) var authManager

    var body: some View {
        NavigationStack {
            Text("Dashboard")
                .foregroundStyle(.secondary)
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out") {
                            Task { await authManager.signOut() }
                        }
                    }
                }
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthManager())
}
