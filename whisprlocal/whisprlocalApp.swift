//
//  whisprlocalApp.swift
//  whisprlocal
//
//  Created by Benjamin van der Woerd on 2025-02-17.
//

import SwiftUI
import SwiftWhisper

@main
struct WhisprlocalApp: App {
    // Add state objects for managing transcription and audio recording
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @StateObject private var audioRecorder = AudioRecorder.shared
    @State private var isTranscriptionWindowShown = false
    
    var body: some Scene {
        MenuBarExtra("Whisprlocal", systemImage: audioRecorder.isRecording ? "waveform.circle.fill" : "waveform") {
            VStack(spacing: 12) {
                if transcriptionManager.isModelLoaded {
                    Text("Model loaded")
                        .foregroundColor(.green)
                } else {
                    Text("Model not loaded")
                        .foregroundColor(.red)
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
                }
                
                // Recent transcriptions list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(transcriptionManager.recentTranscriptions) { entry in
                            TranscriptionEntryView(entry: entry, isHovered: false)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 200)
                
                Divider()
                
                Button(audioRecorder.isRecording ? "Stop Recording" : "Start Recording") {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                    } else {
                        if !transcriptionManager.isModelLoaded {
                            let alert = NSAlert()
                            alert.messageText = "No Model Loaded"
                            alert.informativeText = "Please go to Preferences and download a model first."
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            return
                        }
                        print("Starting recording...")
                        audioRecorder.startRecording()
                    }
                }
                .keyboardShortcut("r")
                
                Divider()
                
                SettingsLink {
                    Text("Preferences...")
                }
                .keyboardShortcut(",")
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            PreferencesView()
                .environmentObject(transcriptionManager)
        }
    }
}

// TranscriptionEntryView has been moved to a separate file to avoid redeclaration

