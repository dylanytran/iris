//
//  VoiceAssistant.swift
//  treehacks
//
//  Advanced voice assistant that intercepts voice queries and routes them
//  through OpenAI function calling. Has access to:
//    - search_memory   – semantic clip search
//    - list_tasks / add_task / update_task / delete_task  – todo CRUD
//    - list_contacts / search_contacts  – contact read
//  Returns a verbose natural-language response (and optionally a clip result).
//

import Foundation
import AVFoundation

// MARK: - Response

/// The result returned by the voice assistant after processing a query.
struct VoiceAssistantResponse {
    let answer: String
    let clipResult: ClipSearchResult?
}

// MARK: - Errors

enum VoiceAssistantError: Error, LocalizedError {
    case apiError(statusCode: Int, body: String)
    case parseError
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .apiError(let code, _): return "API error (HTTP \(code))"
        case .parseError:            return "Failed to parse API response"
        case .noAPIKey:              return "No OpenAI API key configured"
        }
    }
}

// MARK: - VoiceAssistant

final class VoiceAssistant {

    // MARK: - Dependencies

    private let searchEngine: ClipSearchEngine
    private let taskStore: TaskStore
    private let contactStore: ContactStore

    /// Populated if a `search_memory` tool call succeeds during processing.
    private var lastClipResult: ClipSearchResult?

    // MARK: - API Configuration

    private static let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "gpt-4o-mini"

    // MARK: - System Prompt

    private static func systemPrompt() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let now = formatter.string(from: Date())

        return """
        You are a helpful voice assistant integrated into a pair of smart glasses. \
        The current date and time is \(now).

        You have five capabilities:

        1. **Memory Search** - Search recent video clips recorded by the glasses. \
        Use `search_memory` when the user asks about something they saw, where they \
        placed an object, or wants to recall a recent event. Do not repeat the context verbatim.

        2. **Task Management** - Manage the user's to-do list. Use the task tools \
        (`list_tasks`, `add_task`, `update_task`, `delete_task`) to list, create, \
        update, or remove tasks. When listing tasks, always call the tool first — \
        do not make up task data.

        3. **Contact Lookup** - Look up people in the user's contact book. Use \
        `search_contacts` to find a specific person or `list_contacts` to show everyone.

        4. **Zoom Calls** - Start a Zoom video call. Use `start_zoom_call` when the user \
        asks to start a Zoom meeting or video call.

        5. **Phone Calls** - Make a phone call to a contact. Use `call_contact` when the user \
        says "call [name]" or "phone [name]". This will look up the contact and dial their number.

        Guidelines:
        - Be helpful, warm, and concise (2-4 sentences).
        - When searching memory, describe what was found naturally.
        - When managing tasks, confirm the action and briefly repeat what changed.
        - When looking up contacts, share the relevant details.
        - When starting a Zoom call, confirm the call is being started.
        - When making a phone call, confirm you're calling the contact.
        - If a user says "call [name]" without specifying Zoom, use `call_contact` for a phone call.
        - If a request is ambiguous, use your best judgment about which tool to use.
        - You may call multiple tools in sequence if needed.
        - Your response will be displayed as text on the user's smart glasses.
        """
    }

    // MARK: - Tool Definitions (JSON)

    /// OpenAI function-calling tool definitions, parsed once from a JSON literal.
    private static let tools: [[String: Any]] = {
        let json = """
        [
            {
                "type": "function",
                "function": {
                    "name": "search_memory",
                    "description": "Search through recent video clips recorded by the smart glasses to find a specific memory. Use when the user asks about something they saw, where they placed an object, or wants to recall a recent event.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The search query describing what to look for in recorded memories"
                            }
                        },
                        "required": ["query"]
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "list_tasks",
                    "description": "List tasks from the user's to-do list. Can filter by status.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "filter": {
                                "type": "string",
                                "enum": ["all", "pending", "completed", "overdue"],
                                "description": "Filter tasks by status. Defaults to 'all'."
                            }
                        },
                        "required": []
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "add_task",
                    "description": "Add a new task to the user's to-do list.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "title": {
                                "type": "string",
                                "description": "The title of the task"
                            },
                            "description": {
                                "type": "string",
                                "description": "Optional longer description of the task"
                            },
                            "due_date": {
                                "type": "string",
                                "description": "Optional due date in ISO 8601 format (e.g. 2026-02-15T14:00:00Z)"
                            }
                        },
                        "required": ["title"]
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "update_task",
                    "description": "Update an existing task. Can mark complete/incomplete or change details. When the user asks to complete a task by name, first call list_tasks to find its ID, then call update_task.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "task_id": {
                                "type": "string",
                                "description": "The UUID of the task to update"
                            },
                            "title": {
                                "type": "string",
                                "description": "New title for the task"
                            },
                            "description": {
                                "type": "string",
                                "description": "New description for the task"
                            },
                            "due_date": {
                                "type": "string",
                                "description": "New due date in ISO 8601 format"
                            },
                            "is_completed": {
                                "type": "boolean",
                                "description": "Whether the task is completed"
                            }
                        },
                        "required": ["task_id"]
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "delete_task",
                    "description": "Delete a task from the to-do list. When the user asks to delete a task by name, first call list_tasks to find its ID, then call delete_task.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "task_id": {
                                "type": "string",
                                "description": "The UUID of the task to delete"
                            }
                        },
                        "required": ["task_id"]
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "list_contacts",
                    "description": "List all contacts stored in the user's contact book.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "search_contacts",
                    "description": "Search contacts by name, relationship, or notes. Use when the user asks about a specific person.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Name, relationship, or keyword to search for"
                            }
                        },
                        "required": ["query"]
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "start_zoom_call",
                    "description": "Start a Zoom video call. Use when the user asks to start a call, start a meeting, or join a video call.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "call_contact",
                    "description": "Make a phone call to a contact. Use when the user says 'call [name]' or 'phone [name]'. This will look up the contact and dial their phone number.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "contact_name": {
                                "type": "string",
                                "description": "The name of the contact to call"
                            }
                        },
                        "required": ["contact_name"]
                    }
                }
            }
        ]
        """.data(using: .utf8)!
        return (try! JSONSerialization.jsonObject(with: json)) as! [[String: Any]]
    }()

    // MARK: - Init

    init(
        searchEngine: ClipSearchEngine,
        taskStore: TaskStore = .shared,
        contactStore: ContactStore = .shared
    ) {
        self.searchEngine = searchEngine
        self.taskStore = taskStore
        self.contactStore = contactStore
    }

    // MARK: - Public API

    /// Process a voice query through the assistant.
    /// Runs a function-calling loop (up to 6 round-trips) and returns
    /// the final text response plus an optional clip result.
    func process(query: String, clips: [IndexedClip]) async throws -> VoiceAssistantResponse {
        guard let apiKey = OpenAIClient.loadAPIKey() else {
            throw VoiceAssistantError.noAPIKey
        }

        lastClipResult = nil

        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt()],
            ["role": "user",   "content": query]
        ]

        // Function-calling loop
        for iteration in 0..<6 {
            print("[VoiceAssistant] Iteration \(iteration), sending \(messages.count) messages")
            let assistantMessage = try await callChatCompletions(messages: messages, apiKey: apiKey)

            // If no tool calls, we have the final answer
            guard let toolCalls = assistantMessage["tool_calls"] as? [[String: Any]],
                  !toolCalls.isEmpty else {
                let content = assistantMessage["content"] as? String
                print("[VoiceAssistant] Final response content: \(content ?? "nil")")
                return VoiceAssistantResponse(answer: content ?? "I'm sorry, I couldn't process that.", clipResult: lastClipResult)
            }

            // Append the assistant's message (including tool_calls) to the conversation
            messages.append(assistantMessage)

            // Execute each tool call and append results
            for toolCall in toolCalls {
                guard let callID   = toolCall["id"] as? String,
                      let function = toolCall["function"] as? [String: Any],
                      let name     = function["name"] as? String,
                      let argsJSON = function["arguments"] as? String else {
                    continue
                }

                let toolResult = await executeTool(name: name, argumentsJSON: argsJSON, clips: clips)
                print("[VoiceAssistant] Tool \(name) → \(toolResult.prefix(200))")

                messages.append([
                    "role":         "tool",
                    "tool_call_id": callID,
                    "content":      toolResult
                ])
            }
        }

        // Safety: loop exhausted
        return VoiceAssistantResponse(
            answer: "I processed your request but couldn't finalize a response.",
            clipResult: lastClipResult
        )
    }

    // MARK: - OpenAI Chat Completions Call

    private func callChatCompletions(messages: [[String: Any]], apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model":      Self.model,
            "messages":   messages,
            "tools":      Self.tools,
            "max_tokens": 400
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VoiceAssistantError.parseError
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[VoiceAssistant] API error \(http.statusCode): \(errorBody)")
            throw VoiceAssistantError.apiError(statusCode: http.statusCode, body: errorBody)
        }

        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw VoiceAssistantError.parseError
        }

        return message
    }

    // MARK: - Tool Dispatch

    private func executeTool(name: String, argumentsJSON: String, clips: [IndexedClip]) async -> String {
        let args: [String: Any]
        if let data = argumentsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = parsed
        } else {
            args = [:]
        }

        switch name {
        case "search_memory":    return executeSearchMemory(args: args, clips: clips)
        case "list_tasks":       return await executeListTasks(args: args)
        case "add_task":         return await executeAddTask(args: args)
        case "update_task":      return await executeUpdateTask(args: args)
        case "delete_task":      return await executeDeleteTask(args: args)
        case "list_contacts":    return await executeListContacts()
        case "search_contacts":  return await executeSearchContacts(args: args)
        case "start_zoom_call":  return await executeStartZoomCall(args: args)
        case "call_contact":     return await executeCallContact(args: args)
        default:                 return jsonString(["error": "Unknown tool: \(name)"])
        }
    }

    // MARK: - Tool: search_memory

    private func executeSearchMemory(args: [String: Any], clips: [IndexedClip]) -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return jsonString(["error": "No query provided"])
        }

        guard let result = searchEngine.findBestClip(for: query, in: clips) else {
            return jsonString([
                "found": false,
                "message": "No matching memory clips were found in the last 60 seconds of recording."
            ] as [String: Any])
        }

        // Store for the caller
        lastClipResult = result

        return jsonString([
            "found":       true,
            "description": result.clip.description,
            "time_ago":    result.clip.timeAgoLabel,
            "score":       result.score,
            "method":      result.method,
            "keywords":    Array(result.clip.keywords).joined(separator: ", ")
        ] as [String: Any])
    }

    // MARK: - Tool: list_tasks

    private func executeListTasks(args: [String: Any]) async -> String {
        let filter = args["filter"] as? String ?? "all"

        let tasks: [TaskItem] = await MainActor.run {
            switch filter {
            case "pending":   return taskStore.tasks.filter { !$0.isCompleted }
            case "completed": return taskStore.tasks.filter {  $0.isCompleted }
            case "overdue":   return taskStore.tasks.filter {  $0.isOverdue   }
            default:          return taskStore.tasks
            }
        }

        let taskDicts: [[String: Any]] = tasks.map { task in
            [
                "id":           task.id.uuidString,
                "title":        task.title,
                "description":  task.taskDescription,
                "due_date":     ISO8601DateFormatter().string(from: task.dueDate),
                "is_completed": task.isCompleted,
                "is_overdue":   task.isOverdue
            ] as [String: Any]
        }

        return jsonString([
            "count":  tasks.count,
            "filter": filter,
            "tasks":  taskDicts
        ] as [String: Any])
    }

    // MARK: - Tool: add_task

    private func executeAddTask(args: [String: Any]) async -> String {
        let title       = args["title"]       as? String ?? "Untitled Task"
        let description = args["description"] as? String ?? ""
        let dueDateStr  = args["due_date"]    as? String

        let dueDate: Date
        if let str = dueDateStr, let parsed = ISO8601DateFormatter().date(from: str) {
            dueDate = parsed
        } else {
            // Default to tomorrow
            dueDate = Date().addingTimeInterval(86400)
        }

        let task = TaskItem(title: title, taskDescription: description, dueDate: dueDate)

        await MainActor.run {
            taskStore.addTask(task)
        }

        return jsonString([
            "success":  true,
            "task_id":  task.id.uuidString,
            "title":    task.title,
            "due_date": ISO8601DateFormatter().string(from: task.dueDate)
        ] as [String: Any])
    }

    // MARK: - Tool: update_task

    private func executeUpdateTask(args: [String: Any]) async -> String {
        guard let idStr = args["task_id"] as? String,
              let taskID = UUID(uuidString: idStr) else {
            return jsonString(["error": "Invalid or missing task_id"])
        }

        return await MainActor.run {
            guard var task = taskStore.tasks.first(where: { $0.id == taskID }) else {
                return jsonString(["error": "Task not found with id \(idStr)"])
            }

            if let t = args["title"]        as? String { task.title = t }
            if let d = args["description"]  as? String { task.taskDescription = d }
            if let c = args["is_completed"] as? Bool   { task.isCompleted = c }
            if let s = args["due_date"]     as? String,
               let date = ISO8601DateFormatter().date(from: s) {
                task.dueDate = date
            }

            taskStore.updateTask(task)

            return jsonString([
                "success":      true,
                "task_id":      task.id.uuidString,
                "title":        task.title,
                "is_completed": task.isCompleted
            ] as [String: Any])
        }
    }

    // MARK: - Tool: delete_task

    private func executeDeleteTask(args: [String: Any]) async -> String {
        guard let idStr = args["task_id"] as? String,
              let taskID = UUID(uuidString: idStr) else {
            return jsonString(["error": "Invalid or missing task_id"])
        }

        return await MainActor.run {
            guard let task = taskStore.tasks.first(where: { $0.id == taskID }) else {
                return jsonString(["error": "Task not found with id \(idStr)"])
            }
            taskStore.deleteTask(task)
            return jsonString([
                "success":       true,
                "deleted_title": task.title
            ] as [String: Any])
        }
    }

    // MARK: - Tool: list_contacts

    private func executeListContacts() async -> String {
        let contacts: [Person] = await MainActor.run { contactStore.contacts }
        return jsonString(contactsPayload(contacts, query: nil))
    }

    // MARK: - Tool: search_contacts

    private func executeSearchContacts(args: [String: Any]) async -> String {
        let query = (args["query"] as? String ?? "").lowercased()
        guard !query.isEmpty else {
            return await executeListContacts()
        }

        let matches: [Person] = await MainActor.run {
            contactStore.contacts.filter { person in
                person.name.lowercased().contains(query)
                || person.relationship.lowercased().contains(query)
                || person.notes.lowercased().contains(query)
                || person.phoneNumber.contains(query)
            }
        }

        return jsonString(contactsPayload(matches, query: query))
    }

    // MARK: - Tool: start_zoom_call

    private func executeStartZoomCall(args: [String: Any]) async -> String {
        // Use a fixed session name for simplicity
        let sessionName = "Iris"
        let userName = args["user_name"] as? String ?? "User"
        
        print("[VoiceAssistant] start_zoom_call args: \(args)")
        print("[VoiceAssistant] Starting Zoom call - session: \(sessionName), user: \(userName)")

        // Ensure SDK is initialized
        await MainActor.run {
            if !ZoomService.shared.isInitialized {
                ZoomService.shared.initializeSDK()
            }
        }

        // Check if already in a session
        let alreadyInSession = await MainActor.run { ZoomService.shared.isInSession }
        if alreadyInSession {
            let msg = "Already in a Zoom call. Please end the current call first."
            await MainActor.run { AppSpeechManager.shared.speak(msg) }
            return jsonString(["success": false, "error": msg] as [String: Any])
        }

        // Start the Zoom call (ZoomService speaks "Starting Zoom Call" when join starts)
        await MainActor.run {
            ZoomService.shared.joinSession(sessionName: sessionName, userName: userName)
        }

        return jsonString([
            "success": true,
            "session_name": sessionName,
            "user_name": userName,
            "message": "Starting Zoom call: \(sessionName)"
        ] as [String: Any])
    }

    // MARK: - Tool: call_contact

    private func executeCallContact(args: [String: Any]) async -> String {
        guard let contactName = args["contact_name"] as? String, !contactName.isEmpty else {
            let msg = "No contact name provided"
            await MainActor.run { AppSpeechManager.shared.speak(msg) }
            return jsonString(["success": false, "error": msg] as [String: Any])
        }

        print("[VoiceAssistant] call_contact for: \(contactName)")

        // Search for the contact
        let query = contactName.lowercased()
        let matches: [Person] = await MainActor.run {
            contactStore.contacts.filter { person in
                person.name.lowercased().contains(query)
            }
        }

        guard let contact = matches.first else {
            let msg = "No contact found with name '\(contactName)'"
            await MainActor.run { AppSpeechManager.shared.speak(msg) }
            return jsonString(["success": false, "error": msg] as [String: Any])
        }

        // Check if contact has a phone number
        guard !contact.phoneNumber.isEmpty else {
            let msg = "\(contact.name) doesn't have a phone number saved"
            await MainActor.run { AppSpeechManager.shared.speak(msg) }
            return jsonString(["success": false, "error": msg] as [String: Any])
        }

        await MainActor.run { AppSpeechManager.shared.speak("Calling \(contact.name)") }

        print("[VoiceAssistant] Calling \(contact.name) at \(contact.phoneNumber)")

        // Initiate the call via VAPI
        return await withCheckedContinuation { continuation in
            VAPIService.shared.callPhoneNumber(contact.phoneNumber, contactName: contact.name) { success in
                if success {
                    continuation.resume(returning: self.jsonString([
                        "success": true,
                        "contact_name": contact.name,
                        "phone_number": contact.phoneNumber,
                        "message": "Calling \(contact.name)"
                    ] as [String: Any]))
                } else {
                    let msg = "Failed to initiate call to \(contact.name)"
                    Task { @MainActor in AppSpeechManager.shared.speak(msg) }
                    continuation.resume(returning: self.jsonString([
                        "success": false,
                        "error": msg
                    ] as [String: Any]))
                }
            }
        }
    }

    // MARK: - Helpers

    private func contactsPayload(_ contacts: [Person], query: String?) -> [String: Any] {
        let dicts: [[String: Any]] = contacts.map { p in
            [
                "id":            p.id,
                "name":          p.name,
                "relationship":  p.relationship,
                "phone_number":  p.phoneNumber,
                "notes":         p.notes,
                "has_face_data": !p.faceEmbeddings.isEmpty
            ] as [String: Any]
        }
        var result: [String: Any] = [
            "count":    contacts.count,
            "contacts": dicts
        ]
        if let q = query { result["query"] = q }
        return result
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str  = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
