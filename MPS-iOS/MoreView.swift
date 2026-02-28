//
//  MoreView.swift
//  MPS-iOS
//

import SwiftUI

struct MoreView: View {
    @Environment(AuthManager.self) var authManager

    @State private var showTasks = false
    @State private var showWorkHistory = false
    @State private var showSpaceSettings = false
    @State private var showAccountSettings = false

    var body: some View {
        NavigationStack {
            List {
                Button { showTasks = true } label: {
                    Label("Tasks", systemImage: "checkmark.circle")
                }
                Button { showWorkHistory = true } label: {
                    Label("Work History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                Button { showSpaceSettings = true } label: {
                    Label("Space Settings", systemImage: "gearshape")
                }
                Button { showAccountSettings = true } label: {
                    Label("Account Settings", systemImage: "person.circle")
                }

                Button(role: .destructive) {
                    Task { await authManager.signOut() }
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .navigationTitle("More")
        }
        .sheet(isPresented: $showTasks) { TasksView() }
        .sheet(isPresented: $showWorkHistory) { WorkHistoryView() }
        .sheet(isPresented: $showSpaceSettings) { SpaceSettingsView() }
        .sheet(isPresented: $showAccountSettings) { AccountSettingsView() }
    }
}
