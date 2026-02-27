//
//  ContentView.swift
//  MPS-iOS
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.bar.fill") {
                DashboardView()
            }
            Tab("Users", systemImage: "person.2.fill") {
                UsersView()
            }
            Tab("Teams", systemImage: "person.3.fill") {
                TeamsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
