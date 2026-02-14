//
//  ContactStore.swift
//  treehacks
//

import Foundation
import Combine
import SwiftUI

/// Shared, observable store for all contacts. Persists to the app's documents directory.
class ContactStore: ObservableObject {
    static let shared = ContactStore()

    @Published var contacts: [Person] = []

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("contacts.json")
        loadContacts()
    }

    // MARK: - Persistence

    func loadContacts() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let payloads = try JSONDecoder().decode([PersonPayload].self, from: data)
                contacts = payloads.map { $0.toPerson() }
            } catch {
                print("[ContactStore] Failed to load from disk: \(error). Falling back to bundle.")
                contacts = PersonLoader.loadFromBundle(filename: nil)
                saveContacts()
            }
        } else {
            // First launch: seed from the bundled JSON
            contacts = PersonLoader.loadFromBundle(filename: nil)
            saveContacts()
        }
        print("[ContactStore] Loaded \(contacts.count) contact(s)")
    }

    func saveContacts() {
        do {
            let payloads = contacts.map { $0.toPayload() }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(payloads)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ContactStore] Failed to save: \(error)")
        }
    }

    // MARK: - CRUD

    func addContact(_ contact: Person) {
        contacts.append(contact)
        saveContacts()
    }

    func updateContact(_ contact: Person) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
            saveContacts()
        }
    }

    func deleteContact(_ contact: Person) {
        contacts.removeAll { $0.id == contact.id }
        saveContacts()
    }

    func deleteContacts(at offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
        saveContacts()
    }
}
