//
//  TasksListView.swift
//  treehacks
//
//  View for displaying and managing user tasks.
//  Layout matches the Contacts list format for visual consistency.
//

import SwiftUI

struct TasksListView: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Tap + to add your first task.")
                    )
                } else {
                    List {
                        ForEach(store.tasks) { task in
                            NavigationLink(destination: TaskDetailView(taskID: task.id)) {
                                TaskRow(task: task)
                            }
                        }
                        .onDelete(perform: store.deleteTasks(at:))
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                TaskFormView(mode: .add)
            }
        }
    }
}

// MARK: - Task Row

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            // Status circle icon (matches contact avatar circle style)
            ZStack {
                Circle()
                    .fill(task.isCompleted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(task.isCompleted ? .green : .accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Due date indicator (matches contact trailing badge style)
            VStack(alignment: .trailing, spacing: 2) {
                Text(task.shortDueDate)
                    .font(.caption)
                    .foregroundStyle(dueDateColor)
                if task.isOverdue {
                    Text("Overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dueDateColor: Color {
        if task.isCompleted { return .green }
        if task.isOverdue { return .red }
        let hoursUntilDue = task.dueDate.timeIntervalSince(Date()) / 3600
        if hoursUntilDue < 24 { return .orange }
        return .secondary
    }
}

// MARK: - Task Detail View

struct TaskDetailView: View {
    let taskID: UUID
    @ObservedObject private var store = TaskStore.shared
    @State private var showingEditSheet = false

    private var task: TaskItem? {
        store.tasks.first { $0.id == taskID }
    }

    var body: some View {
        if let task = task {
            List {
                // Header section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundColor(task.isCompleted ? .green : .accentColor)
                            Text(task.title)
                                .font(.title2.weight(.bold))
                                .strikethrough(task.isCompleted, color: .secondary)
                        }

                        HStack(spacing: 16) {
                            Label(task.formattedDueDate, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if task.isOverdue {
                            Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Description section
                if !task.taskDescription.isEmpty {
                    Section("Description") {
                        Text(task.taskDescription)
                            .font(.body)
                    }
                }

                // Actions section
                Section {
                    Button {
                        var updated = task
                        updated.isCompleted.toggle()
                        store.updateTask(updated)
                    } label: {
                        HStack {
                            Image(systemName: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                            Text(task.isCompleted ? "Mark as Incomplete" : "Mark as Complete")
                        }
                        .foregroundStyle(task.isCompleted ? .orange : .green)
                    }

                    Button(role: .destructive) {
                        store.deleteTask(task)
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Task")
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                TaskFormView(mode: .edit(task))
            }
        } else {
            ContentUnavailableView(
                "Task Not Found",
                systemImage: "exclamationmark.triangle",
                description: Text("This task may have been deleted.")
            )
        }
    }
}

// MARK: - Task Form View (Add / Edit)

struct TaskFormView: View {
    enum Mode {
        case add
        case edit(TaskItem)
    }

    let mode: Mode
    @ObservedObject private var store = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var taskDescription = ""
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                } header: {
                    Text("Title")
                } footer: {
                    Text("e.g., Take medication, Doctor appointment")
                }

                Section {
                    TextEditor(text: $taskDescription)
                        .frame(minHeight: 100)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Add any additional details about this task")
                }

                Section {
                    DatePicker(
                        "Due Date",
                        selection: $dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Due Date")
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if case .edit(let task) = mode {
                    title = task.title
                    taskDescription = task.taskDescription
                    dueDate = task.dueDate
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        switch mode {
        case .add:
            let task = TaskItem(
                title: trimmedTitle,
                taskDescription: taskDescription,
                dueDate: dueDate
            )
            store.addTask(task)
        case .edit(var task):
            task.title = trimmedTitle
            task.taskDescription = taskDescription
            task.dueDate = dueDate
            store.updateTask(task)
        }
    }
}

#Preview {
    TasksListView()
}
