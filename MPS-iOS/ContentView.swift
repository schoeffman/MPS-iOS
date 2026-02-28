//
//  ContentView.swift
//  MPS-iOS
//

import SwiftUI

enum AppTab: Hashable {
    case dashboard, projects, schedules
}

struct ContentView: View {
    @Environment(AuthManager.self) var authManager

    @State private var selectedTab: AppTab = .dashboard
    @State private var showUsers = false
    @State private var showTeams = false
    @State private var showTenure = false
    @State private var showPerformanceCycles = false
    @State private var showTasks = false
    @State private var showWorkHistory = false
    @State private var showSpaceSettings = false
    @State private var showAccountSettings = false

    var body: some View {
        tabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                tabBar
            }
            .sheet(isPresented: $showUsers) { UsersView() }
            .sheet(isPresented: $showTeams) { TeamsView() }
            .sheet(isPresented: $showTenure) { TenureView() }
            .sheet(isPresented: $showPerformanceCycles) { PerformanceCyclesView() }
            .sheet(isPresented: $showTasks) { TasksView() }
            .sheet(isPresented: $showWorkHistory) { WorkHistoryView() }
            .sheet(isPresented: $showSpaceSettings) { SpaceSettingsView() }
            .sheet(isPresented: $showAccountSettings) { AccountSettingsView() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .dashboard: DashboardView()
        case .projects:  ProjectsView()
        case .schedules: SchedulesView()
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                tabItem(title: "Dashboard", icon: "chart.bar.fill", tab: .dashboard)
                peopleItem
                tabItem(title: "Projects", icon: "folder.fill", tab: .projects)
                tabItem(title: "Schedules", icon: "calendar", tab: .schedules)
                moreItem
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(.bar, ignoresSafeAreaEdges: .bottom)
    }

    private func tabItem(title: String, icon: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var moreItem: some View {
        Menu {
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
            Divider()
            Button(role: .destructive) {
                Task { await authManager.signOut() }
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                Text("More")
                    .font(.caption2)
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .transaction { $0.animation = nil }
    }

    private var peopleItem: some View {
        Menu {
            Section("Users") {
                Button { showUsers = true } label: {
                    Label("Users", systemImage: "person.2.fill")
                }
                Button { showTenure = true } label: {
                    Label("Tenure", systemImage: "calendar.badge.clock")
                }
                Button { showPerformanceCycles = true } label: {
                    Label("Performance Cycles", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
            }
            Section {
                Button { showTeams = true } label: {
                    Label("Teams", systemImage: "person.3.fill")
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 22))
                Text("People")
                    .font(.caption2)
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .transaction { $0.animation = nil }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
