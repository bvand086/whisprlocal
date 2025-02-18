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
    
    var body: some View {
        HStack {
            Text(entry.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            
            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
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
