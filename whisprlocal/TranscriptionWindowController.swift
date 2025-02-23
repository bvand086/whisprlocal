import SwiftUI
import AppKit

class TranscriptionWindowController: NSWindowController {
    convenience init(transcriptionManager: TranscriptionManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Transcription"
        window.center()
        window.setFrameAutosaveName("TranscriptionWindow")
        
        let contentView = TranscriptionWindow(transcriptionManager: transcriptionManager)
        window.contentView = NSHostingView(rootView: contentView)
        
        self.init(window: window)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.setContentSize(NSSize(width: 500, height: 600))
        window?.minSize = NSSize(width: 400, height: 500)
    }
}

// Extension to manage window instance
extension TranscriptionWindowController {
    static private var sharedController: TranscriptionWindowController?
    
    static func showWindow() {
        if sharedController == nil {
            sharedController = TranscriptionWindowController(transcriptionManager: TranscriptionManager.shared)
        }
        
        sharedController?.showWindow(nil)
        sharedController?.window?.makeKeyAndOrderFront(nil)
    }
    
    static func closeWindow() {
        sharedController?.close()
        sharedController = nil
    }
} 