import Foundation
import SwiftWhisper

extension Whisper {
    // Initialize our environment hooks when the app starts
    static let _setupPromptHook: Bool = {
        // Set up prompt hook when the app starts
        NotificationCenter.default.addObserver(forName: .whisperWillTranscribe, object: nil, queue: .main) { notification in
            if let promptText = ProcessInfo.processInfo.environment["WHISPER_PROMPT"], !promptText.isEmpty {
                print("🔤 Applying prompt from environment: \"\(promptText)\"")
                // Here you'd ideally call a C function to set the prompt parameter
                // This would require modifying whisper.cpp or SwiftWhisper
            }
        }
        return true
    }()
    
    // Make sure our hook is initialized
    static func ensurePromptHookSetup() {
        _ = _setupPromptHook
    }
}

// This notification needs to be posted before transcription starts
extension Notification.Name {
    static let whisperWillTranscribe = Notification.Name("whisperWillTranscribe")
} 