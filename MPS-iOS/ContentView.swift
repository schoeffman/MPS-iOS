//
//  ContentView.swift
//  MPS-iOS
//

import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadContentView()
        } else {
            TabView {
                Tab("Dashboard", systemImage: "chart.bar.fill") {
                    DashboardView()
                }
                Tab("People", systemImage: "person.2.fill") {
                    PeopleView()
                }
                Tab("Projects", systemImage: "folder.fill") {
                    ProjectsContainerView()
                }
                Tab("Schedules", systemImage: "calendar") {
                    SchedulesView()
                }
                Tab("More", systemImage: "ellipsis.circle") {
                    MoreView()
                }
            }
        }
    }
}

// MARK: - iPad

private enum SidebarItem: Hashable {
    case dashboard, people, projects, schedules
    case tasks, workHistory, spaceSettings, accountSettings
}

private struct iPadContentView: View {
    @Environment(AuthManager.self) var authManager
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                        .tag(SidebarItem.dashboard)
                    Label("People", systemImage: "person.2.fill")
                        .tag(SidebarItem.people)
                    Label("Projects", systemImage: "folder.fill")
                        .tag(SidebarItem.projects)
                    Label("Schedules", systemImage: "calendar")
                        .tag(SidebarItem.schedules)
                }

                Section("More") {
                    Label("Tasks", systemImage: "checkmark.circle")
                        .tag(SidebarItem.tasks)
                    Label("Work History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .tag(SidebarItem.workHistory)
                    Label("Space Settings", systemImage: "gearshape")
                        .tag(SidebarItem.spaceSettings)
                    Label("Account Settings", systemImage: "person.circle")
                        .tag(SidebarItem.accountSettings)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await authManager.signOut() }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("MPS Project Scheduler")
        } detail: {
            switch selection {
            case .dashboard, nil: DashboardView()
            case .people:         PeopleView()
            case .projects:       ProjectsContainerView()
            case .schedules:      SchedulesView()
            case .tasks:          TasksView()
            case .workHistory:    WorkHistoryView()
            case .spaceSettings:  SpaceSettingsView()
            case .accountSettings: AccountSettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
