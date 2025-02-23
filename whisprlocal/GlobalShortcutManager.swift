import Foundation
import HotKey
import AppKit
import SwiftUI

// Text field state structure
private struct TextFieldState {
    var element: AXUIElement
    var text: String
    var selectedRange: NSRange
    var lastUpdateTime: Date
}

class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()
    
    private var transcriptionHotKey: HotKey?
    private var clipboardHotKey: HotKey?
    private let audioRecorder = AudioRecorder.shared
    private let transcriptionManager = TranscriptionManager.shared
    private var clipboardWindowController: NSWindowController?
    private var transcriptionUpdateTimer: Timer?
    private var lastTranscription: String = ""
    
    // Text field state management
    private var currentTextFieldState: TextFieldState?
    private var textUpdateQueue = DispatchQueue(label: "com.whisprlocal.textupdate")
    private var lastTextUpdateError: Date?
    private let errorCooldownInterval: TimeInterval = 1.0
    
    private init() {
        setupGlobalShortcuts()
        // Request accessibility permissions if needed
        requestAccessibilityPermissions()
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Application accessibility trusted: \(trusted)")
    }
    
    private func setupGlobalShortcuts() {
        // Set up ⌘⇧Space for transcription
        transcriptionHotKey = HotKey(keyCombo: KeyCombo(key: .space, modifiers: [.command, .shift]))
        
        transcriptionHotKey?.keyDownHandler = { [weak self] in
            self?.startTranscriptionHotKeyAction()
        }
        
        transcriptionHotKey?.keyUpHandler = { [weak self] in
            self?.endTranscriptionHotKeyAction()
        }
        
        // Set up ⌘⇧K for clipboard history
        clipboardHotKey = HotKey(keyCombo: KeyCombo(key: .k, modifiers: [.command, .shift]))
        clipboardHotKey?.keyDownHandler = { [weak self] in
            self?.toggleClipboardWindow()
        }
    }
    
    private func startTranscriptionHotKeyAction() {
        // Start recording if not already in progress
        if !audioRecorder.isRecording {
            if audioRecorder.microphonePermission != .authorized {
                Task {
                    await audioRecorder.requestMicrophonePermissionIfNeeded()
                }
                return
            }
            
            if !transcriptionManager.isModelLoaded {
                Task {
                    if let modelURL = ModelManager.shared.getLastUsedModelURL() {
                        do {
                            try await transcriptionManager.loadModel(named: modelURL.lastPathComponent)
                            audioRecorder.startRecording()
                            // Don't start timer here anymore
                        } catch {
                            print("Failed to load model: \(error)")
                        }
                    }
                }
                return
            }
            
            audioRecorder.startRecording()
            lastTranscription = ""
            
            // Cache the current text field state
            cacheCurrentTextFieldState()
        }
        
        // Don't start timer here anymore - we'll update text after transcription is complete
    }
    
    private func endTranscriptionHotKeyAction() {
        transcriptionUpdateTimer?.invalidate()
        transcriptionUpdateTimer = nil
        
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
            // Remove the delayed update since we'll handle it when transcription is complete
            currentTextFieldState = nil
        }
    }
    
    private func startTranscriptionUpdateTimer() {
        transcriptionUpdateTimer?.invalidate()
        // Update the active text field every 0.3 seconds while the key is held down
        transcriptionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateActiveTextField()
        }
    }
    
    private func cacheCurrentTextFieldState() {
        guard let focusedElement = getFocusedTextElement() else {
            print("No focused text element found")
            return
        }
        
        // Get current text and selection range
        var value: CFTypeRef?
        var range: CFTypeRef?
        
        let textResult = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &value)
        let rangeResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &range)
        
        if textResult == .success,
           let text = value as? String,
           rangeResult == .success,
           let selectionRange = range as? NSRange {
            currentTextFieldState = TextFieldState(
                element: focusedElement,
                text: text,
                selectedRange: selectionRange,
                lastUpdateTime: Date()
            )
            print("Cached text field state: \(text.count) chars, selection: \(selectionRange)")
        }
    }
    
    private func updateActiveTextField() {
        let transcription = transcriptionManager.transcribedText
        guard !transcription.isEmpty else { return }
        
        // Only update if the transcription has changed
        guard transcription != lastTranscription else { return }
        
        print("📝 Attempting to update text field with transcription: '\(transcription)'")
        
        // Always update clipboard first
        updateClipboardContent(transcription)
        
        // Since this is called after transcription is complete,
        // we should try to get the text field state again
        cacheCurrentTextFieldState()
        
        textUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Try to paste if we have a focused text element
            if let focusedElement = self.getFocusedTextElement() {
                print("✅ Found focused text element, attempting update")
                // Try direct text field update first
                let success = self.tryDirectTextUpdate(focusedElement: focusedElement, text: transcription)
                
                if !success {
                    print("⚠️ Direct update failed, falling back to paste")
                    // If direct update fails, try pasting
                    self.simulateCommandV()
                }
            } else {
                print("⚠️ No focused text element found for paste operation")
            }
        }
    }
    
    private func updateClipboardContent(_ text: String) {
        print("📋 Updating clipboard with: '\(text)'")
        
        // Store original clipboard content
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        // Set new content with retry
        var pasteboardSetSuccess = false
        for _ in 1...3 {
            pasteboard.clearContents()
            pasteboardSetSuccess = pasteboard.setString(text, forType: .string)
            if pasteboardSetSuccess {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        if pasteboardSetSuccess {
            print("✏️ Successfully updated clipboard content")
            // Don't restore the original content - we want to keep the transcription in clipboard
            lastTranscription = text
        } else {
            print("❌ Failed to update clipboard content")
        }
    }
    
    private func simulateCommandV() {
        print("⌨️ Simulating Cmd+V paste")
        
        // Create event source with explicit permissions
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("❌ Failed to create event source")
            return
        }
        source.localEventsSuppressionInterval = 0.0
        
        // Ensure we have proper key codes
        let vKey: CGKeyCode = 0x09  // 'V' key
        let cmdKey: CGEventFlags = .maskCommand
        
        // Create key events
        guard let cmdDown = CGEvent(source: nil),
              let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
              let cmdUp = CGEvent(source: nil) else {
            print("❌ Failed to create keyboard events")
            return
        }
        
        // Set command flag
        cmdDown.flags = cmdKey
        vKeyDown.flags = cmdKey
        vKeyUp.flags = cmdKey
        cmdUp.flags = []
        
        // Post events with small delays
        cmdDown.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        vKeyDown.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        vKeyUp.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        cmdUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
    
    private func tryDirectTextUpdate(focusedElement: AXUIElement, text: String) -> Bool {
        // First try to get current text to verify we can interact with the element
        var currentValue: CFTypeRef?
        let getCurrentResult = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &currentValue)
        
        guard getCurrentResult == .success else {
            print("❌ Cannot read current text value: \(getCurrentResult)")
            return false
        }
        
        // Calculate text update
        let newText: String
        if let currentState = currentTextFieldState {
            newText = calculateTextUpdate(currentText: currentState.text, newTranscription: text)
        } else {
            newText = text
        }
        
        // Try to set the new text
        let setResult = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, newText as CFString)
        
        if setResult == .success {
            // Update cached state
            currentTextFieldState?.text = newText
            currentTextFieldState?.lastUpdateTime = Date()
            lastTranscription = text
            return true
        }
        
        print("❌ Failed to set text value: \(setResult)")
        return false
    }
    
    private func calculateTextUpdate(currentText: String, newTranscription: String) -> String {
        // If current text is empty, just return the new transcription
        guard !currentText.isEmpty else { return newTranscription }
        
        // If new transcription is shorter, something went wrong - use new transcription
        if newTranscription.count < lastTranscription.count {
            return newTranscription
        }
        
        // Get the difference between last transcription and new transcription
        if !lastTranscription.isEmpty {
            let additionalText = String(newTranscription.dropFirst(lastTranscription.count))
            if !additionalText.isEmpty {
                // Append only the new text to the current content
                return currentText + additionalText
            }
        }
        
        // Fallback: replace entire text
        return newTranscription
    }
    
    private func isSameElement(_ element1: AXUIElement, as element2: AXUIElement) -> Bool {
        var pid1: pid_t = 0
        var pid2: pid_t = 0
        
        guard AXUIElementGetPid(element1, &pid1) == .success,
              AXUIElementGetPid(element2, &pid2) == .success else {
            return false
        }
        
        // Compare process IDs and element memory addresses
        return pid1 == pid2 && element1 == element2
    }
    
    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        
        // Add a small delay to ensure the focus has settled
        Thread.sleep(forTimeInterval: 0.1)
        
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        print("🔍 Getting focused element - result: \(result)")
        
        // More detailed error handling
        switch result {
        case .success:
            guard let element = focusedElement else {
                print("❌ Focused element is nil despite success")
                return nil
            }
            let axElement = unsafeBitCast(element, to: AXUIElement.self)
            
            // Get the process ID for debugging
            var pid: pid_t = 0
            let pidResult = AXUIElementGetPid(axElement, &pid)
            if pidResult == .success {
                if let appName = NSRunningApplication(processIdentifier: pid)?.localizedName {
                    print("📱 Focused application: \(appName)")
                }
            }
            
            // Verify it's a text element
            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
            print("🎯 Element role result: \(roleResult)")
            
            if roleResult == .success,
               let roleString = role as? String {
                print("📝 Element role: \(roleString)")
                
                // Include more text input roles and debug info
                let textInputRoles = [
                    "AXTextField",
                    "AXTextArea",
                    "AXComboBox",
                    "AXSearchField",
                    "AXStaticText",
                    "AXTextGroup",
                    "AXWebArea",      // For web-based text inputs
                    "AXDocument",     // For document editors
                    "AXEditor"        // For code editors
                ]
                
                if textInputRoles.contains(roleString) {
                    print("✅ Found valid text element")
                    return axElement
                } else {
                    print("❌ Element role '\(roleString)' not in allowed types")
                    // Try to get parent element's role for debugging
                    var parent: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axElement, kAXParentAttribute as CFString, &parent) == .success,
                       let parentElement = parent {
                        let parentAXElement = unsafeBitCast(parentElement, to: AXUIElement.self)
                        var parentRole: CFTypeRef?
                        if AXUIElementCopyAttributeValue(parentAXElement, kAXRoleAttribute as CFString, &parentRole) == .success,
                           let parentRoleString = parentRole as? String {
                            print("👆 Parent element role: \(parentRoleString)")
                        }
                    }
                }
            } else {
                print("❌ Could not get role for element")
            }
            
        case _ where result.rawValue == -25211:
            print("⚠️ Application is not trusted for Accessibility access")
        case _ where result.rawValue == -25204:
            print("⚠️ No element has keyboard focus")
        default:
            print("⚠️ Unexpected error: \(result)")
        }
        
        return nil
    }
    
    private func pasteTextUsingPasteboard(_ text: String) {
        print("📋 Attempting to paste text: '\(text)'")
        
        // Store original clipboard content
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        print("💾 Saved original clipboard content")
        
        // Set new content with retry
        var pasteboardSetSuccess = false
        for _ in 1...3 {
            pasteboard.clearContents()
            pasteboardSetSuccess = pasteboard.setString(text, forType: .string)
            if pasteboardSetSuccess {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        guard pasteboardSetSuccess else {
            print("❌ Failed to set pasteboard content")
            return
        }
        print("✏️ Set new clipboard content")
        
        // Create event source with explicit permissions
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("❌ Failed to create event source")
            return
        }
        source.localEventsSuppressionInterval = 0.0
        
        // Ensure we have proper key codes
        let vKey: CGKeyCode = 0x09  // 'V' key
        let cmdKey: CGEventFlags = .maskCommand
        
        // Create key events
        guard let cmdDown = CGEvent(source: nil),
              let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
              let cmdUp = CGEvent(source: nil) else {
            print("❌ Failed to create keyboard events")
            return
        }
        
        // Set command flag
        cmdDown.flags = cmdKey
        vKeyDown.flags = cmdKey
        vKeyUp.flags = cmdKey
        cmdUp.flags = []
        
        print("⌨️ Simulating Cmd+V paste")
        
        // Post events with small delays
        cmdDown.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        vKeyDown.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        vKeyUp.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        cmdUp.post(tap: CGEventTapLocation.cghidEventTap)
        
        // Restore original clipboard content after a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let originalContent = originalContent {
                pasteboard.clearContents()
                pasteboard.setString(originalContent, forType: .string)
                print("♻️ Restored original clipboard content")
            }
        }
    }
    
    private func toggleClipboardWindow() {
        if clipboardWindowController == nil {
            let clipboardWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            clipboardWindow.title = "Clipboard History"
            clipboardWindow.center()
            
            let hostingView = NSHostingView(rootView: ClipboardHistoryView())
            clipboardWindow.contentView = hostingView
            
            clipboardWindowController = NSWindowController(window: clipboardWindow)
        }
        
        if clipboardWindowController?.window?.isVisible == true {
            clipboardWindowController?.close()
        } else {
            clipboardWindowController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
} 