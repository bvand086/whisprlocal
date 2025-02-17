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
            
            Button("Preferences...") {
                isShowingPreferences = true
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
        .sheet(isPresented: $isShowingPreferences) {
            PreferencesWindow()
        }
    }
}

#Preview {
    ContentView()
}
