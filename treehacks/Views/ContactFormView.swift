//
//  ContactFormView.swift
//  treehacks
//

import SwiftUI

/// Mode for the contact form: adding a new contact or editing an existing one.
enum ContactFormMode {
    case add
    case edit(Person)
}

struct ContactFormView: View {
    let mode: ContactFormMode
    @ObservedObject private var store = ContactStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var relationship: String = ""
    @State private var phoneNumber: String = ""
    @State private var faceEmbeddings: [[Float]] = []

    // Photo capture state
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var isProcessing = false
    @State private var extractionError: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }

                Section("Relationship") {
                    TextField("e.g. Friend, Coworker, Family", text: $relationship)
                        .autocorrectionDisabled()
                }

                Section("Phone Number") {
                    TextField("Phone number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }

                Section {
                    if isProcessing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Detecting face...")
                                .foregroundStyle(.secondary)
                        }
                    } else if faceEmbeddings.isEmpty {
                        Label("No face embeddings captured", systemImage: "faceid")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(faceEmbeddings.enumerated()), id: \.offset) { index, embedding in
                            HStack {
                                Label(
                                    "Photo \(index + 1) — \(embedding.count)-dim vector",
                                    systemImage: "faceid"
                                )
                                .foregroundStyle(.green)
                                Spacer()
                                Button {
                                    faceEmbeddings.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    if let error = extractionError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Button {
                        showingSourcePicker = true
                    } label: {
                        Label(
                            faceEmbeddings.isEmpty ? "Capture Face" : "Add Another Photo",
                            systemImage: "camera.fill"
                        )
                    }
                    .disabled(isProcessing)

                    if !faceEmbeddings.isEmpty && !isProcessing {
                        Button("Clear All Embeddings", role: .destructive) {
                            faceEmbeddings = []
                            extractionError = nil
                        }
                    }
                } header: {
                    Text("Face Embeddings (\(faceEmbeddings.count))")
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContact()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave || isProcessing)
                }
            }
            .onAppear {
                if case .edit(let person) = mode {
                    name = person.name
                    relationship = person.relationship
                    phoneNumber = person.phoneNumber
                    faceEmbeddings = person.faceEmbeddings
                }
            }
            .confirmationDialog("Choose Photo Source", isPresented: $showingSourcePicker) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        showingCamera = true
                    }
                }
                Button("Choose from Library") {
                    showingPhotoLibrary = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(sourceType: .camera) { image in
                    processImage(image)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    processImage(image)
                }
            }
        }
    }

    // MARK: - Face Embedding Extraction

    private func processImage(_ image: UIImage) {
        isProcessing = true
        extractionError = nil

        // Run Vision on a background thread to keep the UI responsive.
        // Pass the full UIImage so the extractor can read imageOrientation.
        let photo = image
        Task.detached(priority: .userInitiated) {
            let embedding = FaceEmbeddingExtractor.extractEmbedding(from: photo)
            await MainActor.run {
                if let embedding, !embedding.isEmpty {
                    faceEmbeddings.append(embedding)
                    extractionError = nil
                } else {
                    extractionError = "No face detected. Try a clearer, front-facing photo."
                }
                isProcessing = false
            }
        }
    }

    // MARK: - Save

    private func saveContact() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedRelationship = relationship.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let contact = Person(
                id: UUID().uuidString,
                name: trimmedName,
                relationship: trimmedRelationship,
                notes: "",
                phoneNumber: trimmedPhone,
                faceEmbeddings: faceEmbeddings,
                referencePhotos: []
            )
            store.addContact(contact)

        case .edit(let existing):
            var updated = existing
            updated.name = trimmedName
            updated.relationship = trimmedRelationship
            updated.phoneNumber = trimmedPhone
            updated.faceEmbeddings = faceEmbeddings
            store.updateContact(updated)
        }
    }
}

// MARK: - Image Picker (UIImagePickerController wrapper)

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview("Add") {
    ContactFormView(mode: .add)
}
