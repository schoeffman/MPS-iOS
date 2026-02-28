//
//  DashboardView.swift
//  MPS-iOS
//

import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            Text("Dashboard")
                .foregroundStyle(.secondary)
                .navigationTitle("Dashboard")
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthManager())
}
