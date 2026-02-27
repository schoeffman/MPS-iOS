//
//  StaticProjectsView.swift
//  MPS-iOS
//

import SwiftUI

struct StaticProjectsView: View {
    let projects: [Project]

    private var sorted: [Project] {
        projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        List(sorted) { project in
            NavigationLink(destination: StaticProjectDetailView(project: project)) {
                ProjectRow(project: project)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Static Projects")
        .navigationBarTitleDisplayMode(.large)
    }
}
