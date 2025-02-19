import SwiftUI

struct ClipboardHistoryView: View {
    @StateObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var hoveredEntryId: UUID?
    @Environment(\.colorScheme) private var colorScheme
    
    private var filteredEntries: [ClipboardManager.ClipboardEntry] {
        if searchText.isEmpty {
            return clipboardManager.clipboardHistory
        }
        return clipboardManager.clipboardHistory.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search clipboard history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Clipboard history list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredEntries) { entry in
                        ClipboardEntryRow(entry: entry, isHovered: hoveredEntryId == entry.id)
                            .onHover { isHovered in
                                hoveredEntryId = isHovered ? entry.id : nil
                            }
                    }
                }
                .padding(.vertical, 1)
            }
            
            Divider()
            
            // Footer with clear button
            HStack {
                Button(role: .destructive, action: {
                    clipboardManager.clearHistory()
                }) {
                    Label("Clear History", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .opacity(0.8)
                
                Spacer()
                
                Text("\(filteredEntries.count) items")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(8)
        }
    }
}

struct ClipboardEntryRow: View {
    let entry: ClipboardManager.ClipboardEntry
    let isHovered: Bool
    @StateObject private var clipboardManager = ClipboardManager.shared
    
    private var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: entry.type == .transcription ? "waveform" : "doc.text")
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .lineLimit(2)
                    .font(.system(.body, design: .monospaced))
                
                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons (only visible on hover)
            if isHovered {
                HStack(spacing: 12) {
                    Button(action: {
                        clipboardManager.toggleFavorite(entry)
                    }) {
                        Image(systemName: entry.isFavorite ? "star.fill" : "star")
                            .foregroundColor(entry.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        clipboardManager.copyToClipboard(entry)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        clipboardManager.removeEntry(entry)
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(8)
        .background(isHovered ? Color(.selectedTextBackgroundColor).opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            clipboardManager.copyToClipboard(entry)
        }
    }
} 