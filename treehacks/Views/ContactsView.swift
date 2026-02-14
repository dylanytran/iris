//
//  ContactsView.swift
//  treehacks
//

import SwiftUI

struct ContactsView: View {
    @ObservedObject private var store = ContactStore.shared
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Tap + to add your first contact.")
                    )
                } else {
                    List {
                        ForEach(store.contacts) { contact in
                            NavigationLink(destination: ContactDetailView(contactID: contact.id)) {
                                ContactRow(contact: contact)
                            }
                        }
                        .onDelete(perform: store.deleteContacts(at:))
                    }
                }
            }
            .navigationTitle("Contacts")
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
                ContactFormView(mode: .add)
            }
        }
    }
}

// MARK: - Row

private struct ContactRow: View {
    let contact: Person

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(initials(for: contact.name))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.body.weight(.medium))
                Text(contact.relationship)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Face embedding indicator (shows count of reference photos)
            if !contact.faceEmbeddings.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "faceid")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    if contact.faceEmbeddings.count > 1 {
                        Text("\(contact.faceEmbeddings.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map(String.init).joined().uppercased()
    }
}

#Preview {
    ContactsView()
}
