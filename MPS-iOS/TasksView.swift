//
//  TasksView.swift
//  MPS-iOS
//

import SwiftUI

// MARK: - Main View

struct TasksView: View {
    @Environment(AuthManager.self) var authManager

    @State private var tasks: [AppTask] = []
    @State private var pyramidSlots: [Int?] = PriorityStorage.load()
    @State private var medalCounts: MedalCounts = MedalCounts.load()
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var selectedTask: AppTask? = nil
    @State private var error: String?

    private let client = GraphQLClient()

    // MARK: Computed

    private var priorityTaskIds: Set<Int> {
        Set(pyramidSlots.compactMap { $0 })
    }

    private var priorityEntries: [(slot: Int, task: AppTask)] {
        pyramidSlots.enumerated().compactMap { index, taskId in
            guard let id = taskId, let task = tasks.first(where: { $0.id == id }) else { return nil }
            return (slot: index, task: task)
        }
    }

    private var nonPriorityTasks: [AppTask] {
        tasks.filter { !priorityTaskIds.contains($0.id) }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && tasks.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    taskList
                }
            }
            .navigationTitle("Tasks")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                CreateTaskSheet().environment(authManager)
            }
            .sheet(item: $selectedTask, onDismiss: { Task { await load() } }) { task in
                TaskDetailSheet(task: task, pyramidSlots: $pyramidSlots, medalCounts: $medalCounts)
                    .environment(authManager)
            }
            .task { await load() }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: Subviews

    private var taskList: some View {
        List {
            medalRow
            if !priorityEntries.isEmpty {
                prioritySection
            }
            statusSection("New")
            statusSection("Next Up")
            statusSection("Deferred")
        }
    }

    private var medalRow: some View {
        Section {
            HStack {
                Spacer()
                medalBadge("🥇", count: medalCounts.gold)
                Spacer()
                Divider()
                Spacer()
                medalBadge("🥈", count: medalCounts.silver)
                Spacer()
                Divider()
                Spacer()
                medalBadge("🥉", count: medalCounts.bronze)
                Spacer()
            }
            .frame(height: 56)
        }
    }

    private func medalBadge(_ emoji: String, count: Int) -> some View {
        VStack(spacing: 2) {
            Text(emoji).font(.title2)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var prioritySection: some View {
        Section("Priority") {
            ForEach(priorityEntries, id: \.slot) { entry in
                HStack(spacing: 12) {
                    Text(PriorityStorage.medal(forSlot: entry.slot))
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.task.title)
                            .font(.body.weight(.medium))
                        if !entry.task.description.isEmpty {
                            Text(entry.task.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedTask = entry.task }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteTask(entry.task) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ status: String) -> some View {
        let filtered = nonPriorityTasks.filter { $0.status == status }
        if !filtered.isEmpty {
            Section(status) {
                ForEach(filtered) { task in
                    AppTaskRow(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await deleteTask(task) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                CompletedTasksView().environment(authManager)
            } label: {
                Image(systemName: "checkmark.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showCreate = true } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Response: Decodable { let tasks: [AppTask] }
            let result: Response = try await client.fetch(
                query: "{ tasks { id title description status createdAt } }",
                token: token
            )
            tasks = result.tasks
            // Remove pyramid references to tasks that no longer exist
            let existingIds = Set(tasks.map { $0.id })
            var dirty = false
            for i in pyramidSlots.indices {
                if let id = pyramidSlots[i], !existingIds.contains(id) {
                    pyramidSlots[i] = nil
                    dirty = true
                }
            }
            if dirty { PriorityStorage.save(pyramidSlots) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteTask(_ task: AppTask) async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Result: Decodable { let deleteTask: Bool }
            let _: Result = try await client.fetch(
                query: "mutation($id: Int!) { deleteTask(id: $id) }",
                variables: ["id": task.id],
                token: token
            )
            for i in pyramidSlots.indices where pyramidSlots[i] == task.id {
                pyramidSlots[i] = nil
            }
            PriorityStorage.save(pyramidSlots)
            tasks.removeAll { $0.id == task.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Priority & Medal Storage

private enum PriorityStorage {
    private static let slotsKey = "mps.pyramidSlots"

    static func load() -> [Int?] {
        guard let data = UserDefaults.standard.data(forKey: slotsKey),
              let slots = try? JSONDecoder().decode([Int?].self, from: data),
              slots.count == 6
        else { return Array(repeating: nil, count: 6) }
        return slots
    }

    static func save(_ slots: [Int?]) {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: slotsKey)
        }
    }

    static func medal(forSlot slot: Int) -> String {
        if slot == 0 { return "🥇" }
        if slot <= 2 { return "🥈" }
        return "🥉"
    }

    static func tier(forSlot slot: Int) -> String {
        if slot == 0 { return "Gold" }
        if slot <= 2 { return "Silver"  }
        return "Bronze"
    }
}

private struct MedalCounts {
    var gold: Int
    var silver: Int
    var bronze: Int

    static func load() -> MedalCounts {
        MedalCounts(
            gold: UserDefaults.standard.integer(forKey: "mps.medals.gold"),
            silver: UserDefaults.standard.integer(forKey: "mps.medals.silver"),
            bronze: UserDefaults.standard.integer(forKey: "mps.medals.bronze")
        )
    }

    func save() {
        UserDefaults.standard.set(gold, forKey: "mps.medals.gold")
        UserDefaults.standard.set(silver, forKey: "mps.medals.silver")
        UserDefaults.standard.set(bronze, forKey: "mps.medals.bronze")
    }

    mutating func award(forSlot slot: Int) {
        if slot == 0 { gold += 1 }
        else if slot <= 2 { silver += 1 }
        else { bronze += 1 }
        save()
    }
}

// MARK: - Model

fileprivate struct AppTask: Identifiable, Decodable {
    let id: Int
    let title: String
    let description: String
    let status: String
    let createdAt: String
}

// MARK: - Task Row

private struct AppTaskRow: View {
    let task: AppTask

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.title)
                .font(.body.weight(.medium))
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Create Task Sheet

private struct CreateTaskSheet: View {
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var error: String?

    private let client = GraphQLClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Adding…" : "Add") {
                        Task { await create() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
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
    }

    private func create() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        do {
            struct Created: Decodable { let id: Int }
            struct Result: Decodable { let createTask: Created }
            let _: Result = try await client.fetch(
                query: "mutation($input: CreateTaskInput!) { createTask(input: $input) { id } }",
                variables: ["input": ["title": title, "description": description]],
                token: token
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Task Detail Sheet

private struct TaskDetailSheet: View {
    let task: AppTask
    @Binding var pyramidSlots: [Int?]
    @Binding var medalCounts: MedalCounts

    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss

    @State private var currentStatus: String
    @State private var isSaving = false
    @State private var showDeleteAlert = false
    @State private var error: String?

    private let client = GraphQLClient()

    private var slotIndex: Int? {
        pyramidSlots.firstIndex(where: { $0 == task.id })
    }

    private var hasEmptySlot: Bool {
        pyramidSlots.contains(where: { $0 == nil })
    }

    init(task: AppTask, pyramidSlots: Binding<[Int?]>, medalCounts: Binding<MedalCounts>) {
        self.task = task
        _pyramidSlots = pyramidSlots
        _medalCounts = medalCounts
        _currentStatus = State(initialValue: task.status)
    }

    var body: some View {
        NavigationStack {
            List {
                infoSection
                statusSection
                prioritySection
                actionsSection
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Done") {
                        Task { await saveAndDismiss() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .alert("Delete Task", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { Task { await deleteTask() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This task will be permanently removed.")
            }
        }
    }

    private var infoSection: some View {
        Section {
            Text(task.title).font(.body.weight(.medium))
            if !task.description.isEmpty {
                Text(task.description).foregroundStyle(.secondary)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            Picker("Status", selection: $currentStatus) {
                Text("New").tag("New")
                Text("Next Up").tag("Next Up")
                Text("Deferred").tag("Deferred")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var prioritySection: some View {
        Section("Priority") {
            if let idx = slotIndex {
                HStack {
                    Text(PriorityStorage.medal(forSlot: idx))
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PriorityStorage.tier(forSlot: idx))
                            .font(.body.weight(.medium))
                        Text("Slot \(idx + 1) of 6")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        pyramidSlots[idx] = nil
                        PriorityStorage.save(pyramidSlots)
                    }
                    .font(.subheadline)
                }
            } else if hasEmptySlot {
                Button {
                    if let emptyIdx = pyramidSlots.firstIndex(where: { $0 == nil }) {
                        pyramidSlots[emptyIdx] = task.id
                        PriorityStorage.save(pyramidSlots)
                    }
                } label: {
                    Label("Add to Priority", systemImage: "star")
                }
            } else {
                Text("All 6 priority slots are full.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await markComplete() }
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .disabled(isSaving)

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
            .disabled(isSaving)
        }
    }

    private func saveAndDismiss() async {
        if currentStatus != task.status {
            guard let token = authManager.sessionToken else { dismiss(); return }
            isSaving = true
            do {
                struct Updated: Decodable { let id: Int }
                struct Result: Decodable { let updateTaskStatus: Updated }
                let _: Result = try await client.fetch(
                    query: "mutation($id: Int!, $status: String!) { updateTaskStatus(id: $id, status: $status) { id } }",
                    variables: ["id": task.id, "status": currentStatus],
                    token: token
                )
            } catch {
                self.error = error.localizedDescription
                isSaving = false
                return
            }
        }
        dismiss()
    }

    private func markComplete() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        do {
            struct Updated: Decodable { let id: Int }
            struct Result: Decodable { let updateTaskStatus: Updated }
            let _: Result = try await client.fetch(
                query: "mutation($id: Int!, $status: String!) { updateTaskStatus(id: $id, status: $status) { id } }",
                variables: ["id": task.id, "status": "Complete"],
                token: token
            )
            if let idx = slotIndex {
                medalCounts.award(forSlot: idx)
                pyramidSlots[idx] = nil
                PriorityStorage.save(pyramidSlots)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }

    private func deleteTask() async {
        guard let token = authManager.sessionToken else { return }
        isSaving = true
        do {
            struct Result: Decodable { let deleteTask: Bool }
            let _: Result = try await client.fetch(
                query: "mutation($id: Int!) { deleteTask(id: $id) }",
                variables: ["id": task.id],
                token: token
            )
            if let idx = slotIndex {
                pyramidSlots[idx] = nil
                PriorityStorage.save(pyramidSlots)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Completed Tasks

private struct CompletedTasksView: View {
    @Environment(AuthManager.self) var authManager

    @State private var tasks: [AppTask] = []
    @State private var total = 0
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var error: String?

    private let client = GraphQLClient()

    var body: some View {
        Group {
            if isLoading && tasks.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "No Completed Tasks",
                    systemImage: "checkmark.circle",
                    description: Text("Tasks you complete will appear here.")
                )
            } else {
                completedList
            }
        }
        .navigationTitle("Completed")
        .task { await loadPage(1) }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var completedList: some View {
        List {
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.body.weight(.medium))
                    if !task.description.isEmpty {
                        Text(task.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .leading) {
                    Button {
                        Task { await reopen(task) }
                    } label: {
                        Label("Reopen", systemImage: "arrow.uturn.left")
                    }
                    .tint(.orange)
                }
            }
            if tasks.count < total {
                Button {
                    Task { await loadPage(currentPage + 1) }
                } label: {
                    Text("Load More")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isLoading)
            }
        }
    }

    private func loadPage(_ page: Int) async {
        guard let token = authManager.sessionToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            struct PageResult: Decodable { let tasks: [AppTask]; let total: Int }
            struct Response: Decodable { let completedTasks: PageResult }
            let result: Response = try await client.fetch(
                query: "query($page: Int) { completedTasks(page: $page) { tasks { id title description status createdAt } total } }",
                variables: ["page": page],
                token: token
            )
            if page == 1 {
                tasks = result.completedTasks.tasks
            } else {
                tasks.append(contentsOf: result.completedTasks.tasks)
            }
            total = result.completedTasks.total
            currentPage = page
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reopen(_ task: AppTask) async {
        guard let token = authManager.sessionToken else { return }
        do {
            struct Updated: Decodable { let id: Int }
            struct Result: Decodable { let updateTaskStatus: Updated }
            let _: Result = try await client.fetch(
                query: "mutation($id: Int!, $status: String!) { updateTaskStatus(id: $id, status: $status) { id } }",
                variables: ["id": task.id, "status": "New"],
                token: token
            )
            tasks.removeAll { $0.id == task.id }
            total = max(0, total - 1)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    TasksView()
        .environment(AuthManager())
}
