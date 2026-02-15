//
//  TaskItem.swift
//  treehacks
//
//  Model for user tasks with title, description, and due date.
//  Persisted via TaskStore using JSON encoding.
//

import Foundation

struct TaskItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var taskDescription: String
    var dueDate: Date
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        dueDate: Date = Date(),
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

// MARK: - Convenience Extensions

extension TaskItem {
    /// Formatted full due date string
    var formattedDueDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dueDate)
    }

    /// Short due date for list rows
    var shortDueDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today, " + formatter.string(from: dueDate)
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(dueDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: dueDate)
        }
    }

    /// Whether the task is past due
    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }
}
