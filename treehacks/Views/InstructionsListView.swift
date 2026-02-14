//
//  InstructionsListView.swift
//  treehacks
//
//  View for displaying saved call transcripts and instructions.
//  Users can view, edit, and search through past call recordings.
//

import SwiftUI
import SwiftData

struct InstructionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingTranscript.date, order: .reverse) private var transcripts: [MeetingTranscript]
    
    @State private var showZoomCall = false
    @State private var searchText = ""
    @State private var selectedTranscript: MeetingTranscript?
    
    var filteredTranscripts: [MeetingTranscript] {
        if searchText.isEmpty {
            return transcripts
        }
        return transcripts.filter { transcript in
            transcript.title.localizedCaseInsensitiveContains(searchText) ||
            transcript.transcript.localizedCaseInsensitiveContains(searchText) ||
            transcript.instructions.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if transcripts.isEmpty {
                    emptyStateView
                } else {
                    transcriptListView
                }
            }
            .navigationTitle("Instructions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showZoomCall = true }) {
                        Image(systemName: "video.badge.plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search instructions...")
            .sheet(isPresented: $showZoomCall) {
                ZoomCallView()
            }
            .sheet(item: $selectedTranscript) { transcript in
                TranscriptDetailView(transcript: transcript)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Instructions Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start a video call to capture and save instructions from your doctor, caregiver, or family members.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showZoomCall = true }) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Start Video Call")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    // MARK: - Transcript List
    
    private var transcriptListView: some View {
        List {
            ForEach(filteredTranscripts) { transcript in
                Button(action: { selectedTranscript = transcript }) {
                    TranscriptRowView(transcript: transcript)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteTranscripts)
        }
        .listStyle(.insetGrouped)
    }
    
    private func deleteTranscripts(at offsets: IndexSet) {
        for index in offsets {
            let transcript = filteredTranscripts[index]
            modelContext.delete(transcript)
        }
    }
}

// MARK: - Transcript Row View

struct TranscriptRowView: View {
    let transcript: MeetingTranscript
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transcript.title)
                    .font(.headline)
                Spacer()
                Text(transcript.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(transcript.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !transcript.instructions.isEmpty {
                Text(transcript.instructions)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            } else if !transcript.transcript.isEmpty {
                Text(transcript.transcriptPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if !transcript.tags.isEmpty {
                HStack {
                    ForEach(transcript.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Transcript Detail View

struct TranscriptDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var transcript: MeetingTranscript
    
    @State private var editedInstructions: String = ""
    @State private var isEditing = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(transcript.title)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            Label(transcript.formattedDate, systemImage: "calendar")
                            Spacer()
                            Label(transcript.formattedDuration, systemImage: "clock")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Key Instructions Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Key Instructions", systemImage: "list.bullet.clipboard")
                                .font(.headline)
                            Spacer()
                            Button(isEditing ? "Done" : "Edit") {
                                if isEditing {
                                    transcript.instructions = editedInstructions
                                }
                                isEditing.toggle()
                            }
                        }
                        
                        if isEditing {
                            TextEditor(text: $editedInstructions)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        } else {
                            if transcript.instructions.isEmpty {
                                Text("Tap 'Edit' to add key instructions from this call.")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                Text(transcript.instructions)
                                    .font(.body)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Full Transcript Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Full Transcript", systemImage: "doc.text")
                            .font(.headline)
                        
                        if transcript.transcript.isEmpty {
                            Text("No transcript available.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            Text(transcript.transcript)
                                .font(.system(size: 14))
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                editedInstructions = transcript.instructions
            }
        }
    }
}

#Preview {
    InstructionsListView()
        .modelContainer(for: MeetingTranscript.self, inMemory: true)
}
