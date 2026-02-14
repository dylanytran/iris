//
//  PeopleListView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import SwiftUI
import SwiftData

/// Displays all registered people and allows adding/removing profiles.
/// Designed with large, clear elements for accessibility.
struct PeopleListView: View {

    @Query(sort: \Person.dateAdded, order: .reverse) private var people: [Person]
    @Environment(\.modelContext) private var modelContext
    @State private var showAddPerson = false
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    emptyState
                } else {
                    personList
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddPerson = true }) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showAddPerson) {
                AddPersonView(cameraManager: cameraManager)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.5))

            Text("No People Registered")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)

            Text("Add friends and family members so\nthe app can recognize them")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showAddPerson = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Person")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.blue)
                )
            }
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Person List

    private var personList: some View {
        List {
            ForEach(people) { person in
                PersonRow(person: person)
            }
            .onDelete(perform: deletePeople)
        }
        .listStyle(.insetGrouped)
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(people[index])
        }
    }
}

// MARK: - Person Row

struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 16) {
            // Face image
            if let image = person.faceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 2))
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue.opacity(0.4))
                    .frame(width: 60, height: 60)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.system(size: 20, weight: .semibold))

                if !person.relationship.isEmpty {
                    Text(person.relationship)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                if !person.notes.isEmpty {
                    Text(person.notes)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status indicator
            if person.faceDescriptor != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 22))
            } else {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
                    .font(.system(size: 22))
            }
        }
        .padding(.vertical, 6)
    }
}
