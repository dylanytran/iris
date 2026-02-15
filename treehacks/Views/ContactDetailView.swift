//
//  ContactDetailView.swift
//  treehacks
//

import SwiftUI

struct ContactDetailView: View {
    let contactID: String
    @ObservedObject private var store = ContactStore.shared
    @State private var showingEditSheet = false
    @Environment(\.dismiss) private var dismiss

    /// Always read the latest version from the store so edits are reflected.
    private var contact: Person? {
        store.contacts.first { $0.id == contactID }
    }

    var body: some View {
        Group {
            if let contact {
                List {
                    // Header
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 80, height: 80)
                                    Text(initials(for: contact.name))
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                                Text(contact.name)
                                    .font(.title2.weight(.semibold))
                                Text(contact.relationship)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if !contact.phoneNumber.isEmpty {
                                    Text(contact.phoneNumber)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    // Phone Number (tap to call)
                    if !contact.phoneNumber.isEmpty {
                        Section("Phone") {
                            Button {
                                if let url = URL(string: "tel:\(contact.phoneNumber.filter { $0.isNumber })") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Label(contact.phoneNumber, systemImage: "phone.fill")
                                    Spacer()
                                    Image(systemName: "arrow.up.forward.app")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Face Embeddings
                    Section("Face Embeddings") {
                        if contact.faceEmbeddings.isEmpty {
                            Label("Not captured", systemImage: "faceid")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(contact.faceEmbeddings.enumerated()), id: \.offset) { index, embedding in
                                Label(
                                    "Photo \(index + 1) — \(embedding.count)-dim vector",
                                    systemImage: "faceid"
                                )
                                .foregroundStyle(.green)
                            }
                            Text("\(contact.faceEmbeddings.count) reference photo(s)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Danger zone
                    Section {
                        Button(role: .destructive) {
                            store.deleteContact(contact)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Contact")
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle(contact.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            showingEditSheet = true
                        }
                    }
                }
                .sheet(isPresented: $showingEditSheet) {
                    ContactFormView(mode: .edit(contact))
                }
            } else {
                ContentUnavailableView(
                    "Contact Not Found",
                    systemImage: "person.slash",
                    description: Text("This contact may have been deleted.")
                )
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map(String.init).joined().uppercased()
    }
}
