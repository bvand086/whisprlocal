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
    
    var body: some Scene {
        MenuBarExtra("Whisprlocal", systemImage: "waveform") {
            Button(audioRecorder.isRecording ? "Stop Recording" : "Start Recording") {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                } else {
                    audioRecorder.startRecording()
                }
            }
            
            Divider()
            
            Button("Show Transcribed Text") {
                // For demonstration: show the transcribed text in an alert or some UI
                showTranscribedText()
            }
            
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
    
    private func showTranscribedText() {
        let alert = NSAlert()
        alert.messageText = "Transcription"
        alert.informativeText = transcriptionManager.transcribedText.isEmpty
            ? "No text yet."
            : transcriptionManager.transcribedText
        
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
