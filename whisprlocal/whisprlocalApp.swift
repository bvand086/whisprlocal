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
        WindowGroup {
            Color.clear
                .frame(width: 0, height: 0)
                .task {
                    // Try to load the model on app launch
                    do {
                        try await transcriptionManager.loadModel(named: "ggml-base.en.bin")
                    } catch {
                        print("Failed to load model: \(error)")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        .defaultPosition(.topLeading)
        
        // Add a new window for transcriptions
        WindowGroup("Transcriptions") {
            TranscriptionWindowView()
                .environmentObject(transcriptionManager)
        }
        
        MenuBarExtra("Whisprlocal", systemImage: audioRecorder.isRecording ? "waveform.circle.fill" : "waveform") {
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
            
            Divider()
            
            Button("Show Transcriptions") {
                print("Show Transcriptions clicked - Window should appear")
                isTranscriptionWindowShown = true
                NSApp.activate(ignoringOtherApps: true)
                
                // Create a new window if needed
                let windowCount = NSApplication.shared.windows.count
                print("Current window count: \(windowCount)")
            }
            .keyboardShortcut("t")
            
            Divider()
            
            SettingsLink {
                Text("Preferences...")
            }
            .keyboardShortcut(",")
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        
        Settings {
            PreferencesView()
                .environmentObject(transcriptionManager)
        }
    }
}

// Helper view for the transcription window
struct TranscriptionWindowView: View {
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    
    var body: some View {
        ContentView()
            .frame(width: 350, height: 500)
            .onAppear {
                print("TranscriptionWindowView appeared")
            }
            #if DEBUG
            .onAppear {
                print("Debug: View changes will be logged")
                Self._printChanges()
            }
            #endif
    }
}
