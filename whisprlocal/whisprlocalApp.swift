//
//  whisprlocalApp.swift
//  whisprlocal
//
//  Created by Benjamin van der Woerd on 2025-02-17.
//

import SwiftUI
import SwiftWhisper
import AVFoundation

// Add this view for displaying hotkey information
struct HotkeyInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("⌘⇧Space")
                        .font(.system(.body, design: .monospaced))
                        .padding(4)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(4)
                    Text("Start/Stop Recording")
                }
                
                HStack {
                    Text("⌘⇧K")
                        .font(.system(.body, design: .monospaced))
                        .padding(4)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(4)
                    Text("Show Clipboard History")
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}

@main
struct WhisprlocalApp: App {
    // Add state objects for managing transcription and audio recording
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @StateObject private var audioRecorder = AudioRecorder.shared
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var globalShortcutManager = GlobalShortcutManager.shared
    @State private var isTranscriptionWindowShown = false
    @State private var isClipboardHistoryShown = false
    @State private var clipboardWindowController: NSWindowController?
    @State private var isShowingHotkeyInfo = false
    
    var body: some Scene {
        MenuBarExtra("Whisprlocal", systemImage: audioRecorder.isRecording ? "waveform.circle.fill" : "waveform") {
            VStack(spacing: 12) {
                // Status Section
                HStack {
                    if audioRecorder.microphonePermission != .authorized {
                        Label("Microphone Access Required", systemImage: "mic.slash")
                            .foregroundColor(.red)
                    } else if transcriptionManager.isModelLoaded {
                        Label("Model Ready", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("No Model", systemImage: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        isShowingHotkeyInfo = true
                    }) {
                        Image(systemName: "keyboard")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View keyboard shortcuts")
                    .sheet(isPresented: $isShowingHotkeyInfo) {
                        HotkeyInfoView()
                    }
                    
                    if audioRecorder.isRecording {
                        Label("Recording", systemImage: "record.circle")
                            .foregroundColor(.red)
                            .help("Recording in progress")
                    }
                }
                .font(.caption)
                
                // Show microphone permission request if needed
                if audioRecorder.microphonePermission == .denied {
                    VStack(spacing: 4) {
                        Text("Microphone access is required")
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
                
                // Add Transcription Window Button
                Button(action: {
                    TranscriptionWindowController.showWindow()
                }) {
                    Label("Show Transcription Window", systemImage: "waveform.and.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Open transcription window with waveform visualization")
                
                // Processing Status
                if transcriptionManager.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(height: 20)
                        Text("Processing audio...")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                }
                
                // Recent transcriptions list with header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Transcriptions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(transcriptionManager.recentTranscriptions) { entry in
                                TranscriptionEntryView(entry: entry, isHovered: false)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .frame(maxHeight: 200)
                
                Divider()
                
                // Recording Controls
                Button(action: {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                    } else {
                        if audioRecorder.microphonePermission != .authorized {
                            // Request microphone permission
                            Task {
                                await audioRecorder.requestMicrophonePermissionIfNeeded()
                            }
                            return
                        }
                        
                        if !transcriptionManager.isModelLoaded {
                            Task {
                                // Try to load the last used model first
                                if let modelURL = modelManager.getLastUsedModelURL() {
                                    do {
                                        try await transcriptionManager.loadModel(named: modelURL.lastPathComponent)
                                        print("Successfully loaded last used model: \(modelURL.lastPathComponent)")
                                        // Start recording after model is loaded
                                        audioRecorder.startRecording()
                                        return
                                    } catch {
                                        print("Failed to load last used model: \(error)")
                                    }
                                }
                                
                                // If last used model failed or doesn't exist, try any downloaded model
                                if let firstModel = modelManager.downloadedModels.first {
                                    do {
                                        try await transcriptionManager.loadModel(named: firstModel.lastPathComponent)
                                        print("Successfully loaded available model: \(firstModel.lastPathComponent)")
                                        // Start recording after model is loaded
                                        audioRecorder.startRecording()
                                        return
                                    } catch {
                                        print("Failed to load available model: \(error)")
                                    }
                                }
                                
                                // If no models are available or loading failed, try to download the default model
                                do {
                                    let defaultModelName = "ggml-base.en.bin"
                                    let defaultModelURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
                                    try await modelManager.downloadModel(from: defaultModelURL, filename: defaultModelName)
                                    print("Successfully downloaded and loaded default model")
                                    // Start recording after model is loaded
                                    audioRecorder.startRecording()
                                } catch {
                                    print("Failed to download default model: \(error)")
                                    let alert = NSAlert()
                                    alert.messageText = "Failed to Load Model"
                                    alert.informativeText = "Could not load any available models or download a new one. Please go to Preferences to manually download a model."
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                }
                            }
                            return
                        }
                        
                        print("Starting recording...")
                        audioRecorder.startRecording()
                    }
                }) {
                    if modelManager.isDownloadingModel {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(height: 16)
                            Text("Loading Model...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            audioRecorder.isRecording ? "Stop Recording" : "Start Recording",
                            systemImage: audioRecorder.isRecording ? "stop.circle.fill" : "record.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .keyboardShortcut("r")
                .buttonStyle(.bordered)
                .tint(audioRecorder.isRecording ? .red : .blue)
                .help(audioRecorder.isRecording ? "Stop recording (⌘R)" : "Start recording (⌘R)")
                .disabled(audioRecorder.microphonePermission == .denied || modelManager.isDownloadingModel)
                
                // Clipboard History Button
                Button(action: {
                    if let controller = clipboardWindowController {
                        controller.window?.makeKeyAndOrderFront(nil)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    } else {
                        let controller = NSWindowController(window: NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered,
                            defer: false
                        ))
                        controller.window?.title = "Clipboard History"
                        controller.window?.contentView = NSHostingView(rootView: ClipboardHistoryView())
                        controller.window?.center()
                        controller.showWindow(nil)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        clipboardWindowController = controller
                    }
                }) {
                    Label("Show Clipboard History", systemImage: "clipboard")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .buttonStyle(.bordered)
                .help("Show clipboard history (⇧⌘K)")
                
                Divider()
                
                // Settings and Quit
                HStack {
                    SettingsLink {
                        Label("Preferences...", systemImage: "gear")
                    }
                    .keyboardShortcut(",")
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                    .keyboardShortcut("q")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .frame(width: 300)
            .task {
                // Load the last used model on app launch
                if let modelURL = ModelManager.shared.getLastUsedModelURL() {
                    do {
                        try await transcriptionManager.loadModel(named: modelURL.lastPathComponent)
                        print("Successfully loaded last used model: \(modelURL.lastPathComponent)")
                    } catch {
                        print("Failed to load last used model: \(error)")
                    }
                } else {
                    print("No last used model found")
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        WindowGroup("Clipboard History") {
            ClipboardHistoryView()
                .frame(width: 400, height: 500)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 500)
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            PreferencesView()
                .environmentObject(transcriptionManager)
        }
    }
}

// TranscriptionEntryView has been moved to a separate file to avoid redeclaration

