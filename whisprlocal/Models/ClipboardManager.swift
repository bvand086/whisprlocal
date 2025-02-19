import Foundation
import AppKit

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published private(set) var clipboardHistory: [ClipboardEntry] = []
    private let maxHistoryItems = 50
    private let pasteboard = NSPasteboard.general
    private let userDefaultsKey = "clipboardHistory"
    
    private init() {
        loadHistory()
        // Initialize with current clipboard content if it exists
        if let currentText = pasteboard.string(forType: .string) {
            addToHistory(text: currentText, type: .text)
        }
    }
    
    struct ClipboardEntry: Identifiable, Equatable, Codable {
        let id: UUID
        let content: String
        let timestamp: Date
        let type: ClipboardType
        var isFavorite: Bool
        
        init(content: String, timestamp: Date, type: ClipboardType, isFavorite: Bool = false) {
            self.id = UUID()
            self.content = content
            self.timestamp = timestamp
            self.type = type
            self.isFavorite = isFavorite
        }
        
        static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    enum ClipboardType: String, Codable {
        case text
        case transcription
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(clipboardHistory) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decodedHistory = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            DispatchQueue.main.async {
                self.clipboardHistory = decodedHistory
            }
        }
    }
    
    func addToHistory(text: String, type: ClipboardType) {
        // Don't add empty strings or duplicates
        guard !text.isEmpty,
              !clipboardHistory.contains(where: { $0.content == text }) else {
            return
        }
        
        DispatchQueue.main.async {
            // Add new entry at the beginning
            self.clipboardHistory.insert(
                ClipboardEntry(content: text, timestamp: Date(), type: type),
                at: 0
            )
            
            // Keep only the most recent items
            if self.clipboardHistory.count > self.maxHistoryItems {
                self.clipboardHistory.removeLast()
            }
            
            self.saveHistory()
        }
    }
    
    func copyToClipboard(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.content, forType: .string)
        
        // Move the copied item to the top of the history
        if let index = clipboardHistory.firstIndex(of: entry) {
            DispatchQueue.main.async {
                let entry = self.clipboardHistory.remove(at: index)
                self.clipboardHistory.insert(entry, at: 0)
                self.saveHistory()
            }
        }
    }
    
    func toggleFavorite(_ entry: ClipboardEntry) {
        if let index = clipboardHistory.firstIndex(of: entry) {
            DispatchQueue.main.async {
                var updatedEntry = entry
                updatedEntry.isFavorite.toggle()
                self.clipboardHistory[index] = updatedEntry
                self.saveHistory()
            }
        }
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.clipboardHistory.removeAll()
            self.saveHistory()
        }
    }
    
    func removeEntry(_ entry: ClipboardEntry) {
        if let index = clipboardHistory.firstIndex(of: entry) {
            DispatchQueue.main.async {
                self.clipboardHistory.remove(at: index)
                self.saveHistory()
            }
        }
    }
} 