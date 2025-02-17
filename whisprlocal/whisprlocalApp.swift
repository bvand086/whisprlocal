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
    // Add state object for managing transcription
    @StateObject private var transcriptionManager = TranscriptionManager()
    
    var body: some Scene {
        MenuBarExtra("Whisprlocal", systemImage: "waveform") {
            ContentView()
                .environmentObject(transcriptionManager)
        }
    }
}
