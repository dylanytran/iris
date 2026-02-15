//
//  TaskStore.swift
//  treehacks
//
//  Shared, observable store for all tasks.
//  Persists to the app's documents directory as JSON.
//

import Foundation
import Combine

/// Shared, observable store for all tasks. Persists to the app's documents directory.
class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published var tasks: [TaskItem] = []

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("tasks.json")
        loadTasks()
    }

    // MARK: - Persistence

    func loadTasks() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            tasks = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            tasks = try decoder.decode([TaskItem].self, from: data)
        } catch {
            print("[TaskStore] Failed to load from disk: \(error)")
            tasks = []
        }
        print("[TaskStore] Loaded \(tasks.count) task(s)")
    }

    func saveTasks() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[TaskStore] Failed to save: \(error)")
        }
    }

    // MARK: - CRUD

    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
    }

    func updateTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            saveTasks()
        }
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }

    func deleteTasks(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        saveTasks()
    }
}
