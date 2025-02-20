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
    
    // Properties for double-tap detection
    private var lastKeyPressTime: Date?
    private let doubleTapTimeThreshold: TimeInterval = 0.3 // 300ms window for double-tap
    private var isHoldMode = false
    private var isDoubleTapMode = false
    
    private init() {
        setupGlobalShortcuts()
        setupTranscriptionHandler()
    }
    
    private func setupTranscriptionHandler() {
        transcriptionManager.onTranscriptionUpdate = { [weak self] text in
            self?.handleTranscriptionUpdate(text)
        }
    }
    
    private func handleTranscriptionUpdate(_ text: String) {
        // Only paste if we're actively recording
        guard audioRecorder.isRecording else { return }
        
        // Paste the text
        pasteText(text)
    }
    
    private func setupGlobalShortcuts() {
        // Set up ⌘⇧Space for recording
        recordingHotKey = HotKey(keyCombo: KeyCombo(key: .space, modifiers: [.command, .shift]))
        
        // Handle key down
        recordingHotKey?.keyDownHandler = { [weak self] in
            self?.handleKeyDown()
        }
        
        // Handle key up
        recordingHotKey?.keyUpHandler = { [weak self] in
            self?.handleKeyUp()
        }
        
        // Set up ⌘⇧K for clipboard history
        clipboardHotKey = HotKey(keyCombo: KeyCombo(key: .k, modifiers: [.command, .shift]))
        clipboardHotKey?.keyDownHandler = { [weak self] in
            self?.toggleClipboardWindow()
        }
    }
    
    private func handleKeyDown() {
        let now = Date()
        
        if let lastPress = lastKeyPressTime,
           now.timeIntervalSince(lastPress) < doubleTapTimeThreshold {
            // Double-tap detected
            isDoubleTapMode = true
            isHoldMode = false
            toggleRecording()
        } else {
            // Single press - start hold mode
            isHoldMode = true
            isDoubleTapMode = false
            startRecording()
        }
        
        lastKeyPressTime = now
    }
    
    private func handleKeyUp() {
        guard isHoldMode else { return }
        
        // If we're in hold mode and the key is released, stop recording
        isHoldMode = false
        stopRecording()
    }
    
    private func startRecording() {
        guard !audioRecorder.isRecording else { return }
        
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
        
        // Clear any existing text in the active text field before starting
        clearActiveTextFieldContent()
        audioRecorder.startRecording()
    }
    
    private func clearActiveTextFieldContent() {
        // Simulate Command+A to select all
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down for Command
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        // Key down for A
        let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true)
        aDown?.flags = .maskCommand
        aDown?.post(tap: .cghidEventTap)
        
        // Key up for A
        let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false)
        aUp?.flags = .maskCommand
        aUp?.post(tap: .cghidEventTap)
        
        // Key up for Command
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
        
        // Small delay to ensure selection is complete
        usleep(50000) // 50ms delay
        
        // Simulate Delete key to remove selected text
        let deleteDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
        deleteDown?.post(tap: .cghidEventTap)
        
        let deleteUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
        deleteUp?.post(tap: .cghidEventTap)
    }
    
    private func stopRecording() {
        guard audioRecorder.isRecording else { return }
        
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
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            stopRecording()
        } else {
            startRecording()
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