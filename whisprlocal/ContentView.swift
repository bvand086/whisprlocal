//
//  ContentView.swift
//  whisprlocal
//
//  Created by Benjamin van der Woerd on 2025-02-17.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var transcriptionManager: TranscriptionManager
    @State private var isShowingPreferences = false
    @State private var hoveredTranscriptionId: UUID?
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Whisprlocal")
                .font(.headline)
            
            if transcriptionManager.isModelLoaded {
                Text("Model loaded")
                    .foregroundColor(.green)
            } else {
                Text("Model not loaded")
                    .foregroundColor(.red)
            }
            
            if let error = transcriptionManager.currentError {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Divider()
            
            // Show processing status
            if transcriptionManager.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(height: 20)
                    Text("Processing audio...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
            
            // Recent transcriptions list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(transcriptionManager.recentTranscriptions) { entry in
                        TranscriptionEntryView(entry: entry, isHovered: hoveredTranscriptionId == entry.id)
                            .onHover { isHovered in
                                hoveredTranscriptionId = isHovered ? entry.id : nil
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 200)
            
            Divider()
            
            Button("Preferences...") {
                isShowingPreferences = true
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 350)
        .sheet(isPresented: $isShowingPreferences) {
            PreferencesWindow()
        }
    }
}

struct TranscriptionEntryView: View {
    let entry: TranscriptionEntry
    let isHovered: Bool
    
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(formattedTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            
            Text(entry.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.tail)
            
            if isHovered {
                Menu {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    }) {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(formattedTimestamp): \(entry.text)", forType: .string)
                    }) {
                        Label("Copy with Timestamp", systemImage: "clock.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24, height: 24)
                .help("Copy options")
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .cornerRadius(6)
    }
}

#Preview {
    ContentView()
}
