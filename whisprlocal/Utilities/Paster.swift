import Foundation
import Quartz

class Paster {
    /// Simulates a Command+V keystroke to paste the current clipboard contents into the active text field.
    static func pasteText() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            print("Error: Unable to create CGEventSource")
            return
        }
        
        // Virtual key code for 'V' is 9 on macOS
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            print("Error: Unable to create keyboard events")
            return
        }
        
        // Set the command flag to simulate Cmd+V
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Post the key events to simulate paste in the active application
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
} 