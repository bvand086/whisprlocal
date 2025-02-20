import Foundation
import HotKey
import AppKit
import SwiftUI

class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()
    
    private var recordingHotKey: HotKey?
    private var clipboardHotKey: HotKey?
    private let audioRecorder = AudioRecorder.shared
    private let transcriptionManager = TranscriptionManager.shared
    private var clipboardWindowController: NSWindowController?
    
    private init() {
        setupGlobalShortcuts()
    }
    
    private func setupGlobalShortcuts() {
        // Set up ⌘⇧Space for recording
        recordingHotKey = HotKey(keyCombo: KeyCombo(key: .space, modifiers: [.command, .shift]))
        recordingHotKey?.keyDownHandler = { [weak self] in
            self?.toggleRecording()
        }
        
        // Set up ⌘⇧K for clipboard history
        clipboardHotKey = HotKey(keyCombo: KeyCombo(key: .k, modifiers: [.command, .shift]))
        clipboardHotKey?.keyDownHandler = { [weak self] in
            self?.toggleClipboardWindow()
        }
    }
    
    private func toggleClipboardWindow() {
        if let controller = clipboardWindowController {
            if controller.window?.isVisible == true {
                controller.close()
            } else {
                controller.window?.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
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
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
            // Wait for transcription to complete and then paste
            Task {
                // Wait for a short delay to allow transcription to complete
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await MainActor.run {
                    if let text = transcriptionManager.recentTranscriptions.first?.text {
                        self.pasteText(text)
                    }
                }
            }
        } else {
            if audioRecorder.microphonePermission != .authorized {
                Task {
                    await audioRecorder.requestMicrophonePermissionIfNeeded()
                }
                return
            }
            
            if !transcriptionManager.isModelLoaded {
                // Try to load the model
                Task {
                    if let modelURL = ModelManager.shared.getLastUsedModelURL() {
                        do {
                            try await transcriptionManager.loadModel(named: modelURL.lastPathComponent)
                            audioRecorder.startRecording()
                        } catch {
                            print("Failed to load model: \(error)")
                        }
                    }
                }
                return
            }
            
            audioRecorder.startRecording()
        }
    }
    
    private func pasteText(_ text: String) {
        // First, copy the text to the clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Then simulate ⌘V to paste
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down for Command
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        // Key down for V
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        
        // Key up for V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
        
        // Key up for Command
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
} 