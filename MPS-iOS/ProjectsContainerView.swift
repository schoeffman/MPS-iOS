//
//  ProjectsContainerView.swift
//  MPS-iOS
//

import SwiftUI

struct ProjectsContainerView: View {
    enum Section: String, CaseIterable {
        case projects = "Projects"
        case staticProjects = "Static Projects"
    }

    @State private var selectedSection: Section = .projects

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(Section.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                sectionContent
            }
            .navigationTitle("Projects")
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .projects:       ProjectsView(embedded: true)
        case .staticProjects: StaticProjectsView(embedded: true)
        }
    }
}
