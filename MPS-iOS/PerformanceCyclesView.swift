//
//  PerformanceCyclesView.swift
//  MPS-iOS
//

import SwiftUI

struct PerformanceCyclesView: View {
    var embedded = false

    @Environment(AuthManager.self) var authManager

    @State private var cycles: [PCycleSummary] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var editingCycle: PCycleSummary? = nil
    @State private var deletingCycle: PCycleSummary? = nil
    @State private var error: String?

    private let client = GraphQLClient()

    var body: some View {
        if embedded {
            cyclesContent
        } else {
            NavigationStack { cyclesContent }
        }
    }

    private var cyclesContent: some View {
        Group {
            if isLoading && cycles.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cycles.isEmpty {
                ContentUnavailableView(
                    "No Performance Cycles",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text("Tap + to create your first cycle.")
                )
            } else {
                cyclesList
            }
        }
        .navigationTitle("Performance Cycles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            CreateEditCycleSheet().environment(authManager)
        }
        .sheet(item: $editingCycle, onDismiss: { Task { await load() } }) { cycle in
            CreateEditCycleSheet(existing: cycle).environment(authManager)
        }
        .alert("Delete Cycle", isPresented: Binding(
            get: { deletingCycle != nil },
            set: { if !$0 { deletingCycle = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let c = deletingCycle { Task { await deleteCycle(c) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(deletingCycle?.title ?? "")\" will be permanently removed.")
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var cyclesList: some View {
        List {
            ForEach(cycles) { cycle in
                NavigationLink(destination: PerformanceCycleDetailView(cycleId: cycle.id, title: cycle.title)) {
                    CycleRow(cycle: cycle)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deletingCycle = cycle } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { editingCycle = cycle } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Resp: Decodable { let performanceCycles: [PCycleSummary] }
            let result: Resp = try await client.fetch(
                query: "{ performanceCycles { id title cycleMonth users { id fullName } createdAt } }",
                token: token
            )
            cycles = result.performanceCycles
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }

    private func deleteCycle(_ cycle: PCycleSummary) async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Resp: Decodable { let deletePerformanceCycle: Bool }
            let _: Resp = try await client.fetch(
                query: "mutation($id: Int!) { deletePerformanceCycle(id: $id) }",
                variables: ["id": cycle.id],
                token: token
            )
            cycles.removeAll { $0.id == cycle.id }
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
        deletingCycle = nil
    }
}

// MARK: - Cycle Row

private struct CycleRow: View {
    let cycle: PCycleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cycle.title).font(.body.weight(.medium))
            HStack(spacing: 4) {
                Text(pcFormatMonth(cycle.cycleMonth))
                Text("·")
                Text("\(cycle.users.count) \(cycle.users.count == 1 ? "member" : "members")")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Create / Edit Sheet

private struct CreateEditCycleSheet: View {
    var existing: PCycleSummary? = nil

    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedYear  = Calendar.current.component(.year,  from: Date())
    @State private var availableUsers: [UserOption] = []
    @State private var selectedUserIds: Set<Int> = []
    @State private var isLoadingUsers = false
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()
    private let monthNames = Calendar.current.monthSymbols
    private var years: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 2)...(y + 2))
    }

    struct UserOption: Identifiable, Decodable {
        let id: Int
        let fullName: String
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                usersSection
            }
            .navigationTitle(existing == nil ? "New Cycle" : "Edit Cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : existing == nil ? "Create" : "Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .task { await setup() }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
            Picker("Month", selection: $selectedMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(monthNames[m - 1]).tag(m)
                }
            }
            Picker("Year", selection: $selectedYear) {
                ForEach(years, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
        }
    }

    private var usersSection: some View {
        Section("Members") {
            if isLoadingUsers {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ForEach(availableUsers) { user in
                    Button {
                        if selectedUserIds.contains(user.id) {
                            selectedUserIds.remove(user.id)
                        } else {
                            selectedUserIds.insert(user.id)
                        }
                    } label: {
                        HStack {
                            Text(user.fullName).foregroundStyle(.primary)
                            Spacer()
                            if selectedUserIds.contains(user.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func setup() async {
        guard let token = authManager.sessionToken else { return }
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            struct Resp: Decodable { let users: [UserOption] }
            let result: Resp = try await client.fetch(
                query: "{ users { id fullName } }",
                token: token
            )
            availableUsers = result.users.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
            if let existing {
                title = existing.title
                let parts = existing.cycleMonth.split(separator: "-")
                if parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) {
                    selectedYear = y; selectedMonth = m
                }
                selectedUserIds = Set(existing.users.map { $0.id })
            } else {
                selectedUserIds = Set(availableUsers.map { $0.id })
            }
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        defer { isSaving = false }
        let monthStr = String(format: "%04d-%02d", selectedYear, selectedMonth)
        let userIds  = Array(selectedUserIds)
        do {
            if let existing {
                struct Resp: Decodable { struct C: Decodable { let id: Int }; let updatePerformanceCycle: C }
                let _: Resp = try await client.fetch(
                    query: "mutation($id: Int!, $input: UpdatePerformanceCycleInput!) { updatePerformanceCycle(id: $id, input: $input) { id } }",
                    variables: ["id": existing.id, "input": ["title": title, "cycleMonth": monthStr, "userIds": userIds]],
                    token: token
                )
            } else {
                struct Resp: Decodable { struct C: Decodable { let id: Int }; let createPerformanceCycle: C }
                let _: Resp = try await client.fetch(
                    query: "mutation($input: CreatePerformanceCycleInput!) { createPerformanceCycle(input: $input) { id } }",
                    variables: ["input": ["title": title, "cycleMonth": monthStr, "userIds": userIds]],
                    token: token
                )
            }
            dismiss()
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Models

fileprivate struct PCycleSummary: Identifiable, Decodable {
    let id: Int
    let title: String
    let cycleMonth: String
    let users: [PCycleSummaryUser]
    let createdAt: String
}

fileprivate struct PCycleSummaryUser: Identifiable, Decodable {
    let id: Int
    let fullName: String
}

// MARK: - Helpers

fileprivate func pcFormatMonth(_ cycleMonth: String) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM"
    guard let date = fmt.date(from: cycleMonth) else { return cycleMonth }
    let display = DateFormatter()
    display.dateFormat = "MMMM yyyy"
    return display.string(from: date)
}

// MARK: - Preview

#Preview {
    PerformanceCyclesView()
        .environment(AuthManager())
}
