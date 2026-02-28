//
//  ScheduleGraphsView.swift
//  MPS-iOS
//

import SwiftUI
import Charts

struct ScheduleGraphsView: View {
    let assignments: [(userId: Int, projectId: Int, weekStart: String)]
    let projects: [ScheduleAssignedProject]
    let projectTypes: [Int: String]
    let totalMemberWeeks: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if assignments.isEmpty {
                    ContentUnavailableView(
                        "No Assignments",
                        systemImage: "chart.pie",
                        description: Text("No assignments have been made for this schedule.")
                    )
                } else {
                    Section("By Project") {
                        projectChart
                        ForEach(byProject, id: \.name) { stat in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(stat.color == "unassigned" ? Color(.systemGray4) : (Color(hex: stat.color) ?? .accentColor))
                                    .frame(width: 10, height: 10)
                                Text(stat.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(stat.count) week\(stat.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("By Project Type") {
                        typeChart
                        ForEach(Array(byProjectType.enumerated()), id: \.offset) { _, stat in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(typeColor(at: byProjectType.firstIndex(where: { $0.rawType == stat.rawType }) ?? 0))
                                    .frame(width: 10, height: 10)
                                Text(stat.displayType)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(stat.count) week\(stat.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule Graphs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Charts

    private var projectChart: some View {
        Chart(byProject, id: \.name) { stat in
            SectorMark(
                angle: .value("Weeks", stat.count),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(stat.color == "unassigned" ? Color(.systemGray4) : (Color(hex: stat.color) ?? .accentColor))
            .cornerRadius(4)
        }
        .frame(height: 220)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    private var typeChart: some View {
        Chart(Array(byProjectType.enumerated()), id: \.offset) { index, stat in
            SectorMark(
                angle: .value("Weeks", stat.count),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(typeColor(at: index))
            .cornerRadius(4)
        }
        .frame(height: 220)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    // MARK: - Data

    private struct ProjectStat {
        let name: String
        let color: String
        let count: Int
    }

    private struct TypeStat {
        let rawType: String
        let displayType: String
        let count: Int
    }

    private var unassignedCount: Int {
        max(0, totalMemberWeeks - assignments.count)
    }

    private var byProject: [ProjectStat] {
        var counts: [Int: Int] = [:]
        for a in assignments { counts[a.projectId, default: 0] += 1 }
        let map = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var stats = counts.compactMap { id, count -> ProjectStat? in
            guard let p = map[id] else { return nil }
            return ProjectStat(name: p.name, color: p.color, count: count)
        }.sorted { $0.count > $1.count }
        if unassignedCount > 0 {
            stats.append(ProjectStat(name: "Unassigned", color: "unassigned", count: unassignedCount))
        }
        return stats
    }

    private var byProjectType: [TypeStat] {
        var counts: [String: Int] = [:]
        for a in assignments {
            let raw = projectTypes[a.projectId] ?? "Unknown"
            counts[raw, default: 0] += 1
        }
        var stats = counts.map { raw, count -> TypeStat in
            let display = ProjectType(rawValue: raw)?.displayName ?? raw
            return TypeStat(rawType: raw, displayType: display, count: count)
        }.sorted { $0.count > $1.count }
        if unassignedCount > 0 {
            stats.append(TypeStat(rawType: "Unassigned", displayType: "Unassigned", count: unassignedCount))
        }
        return stats
    }

    private let typeColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .yellow]

    private func typeColor(at index: Int) -> Color {
        guard index < byProjectType.count else { return .gray }
        if byProjectType[index].rawType == "Unassigned" { return Color(.systemGray4) }
        return typeColors[index % typeColors.count]
    }
}
