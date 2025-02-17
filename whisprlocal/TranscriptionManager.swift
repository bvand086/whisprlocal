import Foundation
import SwiftWhisper

class TranscriptionManager: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var currentError: Error?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    
    private var whisper: Whisper?
    
    // Model management
    private let modelsFolderURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsPath = appSupport.appendingPathComponent("Whisprlocal/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)
        return modelsPath
    }()
    
    func loadModel(named modelName: String) async throws {
        let modelURL = modelsFolderURL.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelNotFound
        }
        
        // The Whisper initialization can throw
        whisper = try Whisper(fromFileURL: modelURL)
        await MainActor.run {
            isModelLoaded = true
        }
    }
    
    func downloadModel(url: URL, filename: String) async throws {
        let destinationURL = modelsFolderURL.appendingPathComponent(filename)
        
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }
        
        // Using the async/await version of download without progress tracking
        let (downloadURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscriptionError.downloadFailed
        }
        
        try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
        
        await MainActor.run {
            isDownloading = false
            downloadProgress = 1.0
        }
        
        try await loadModel(named: filename)
    }
    
    enum TranscriptionError: LocalizedError {
        case modelNotFound
        case downloadFailed
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "The specified model file could not be found"
            case .downloadFailed:
                return "Failed to download the model file"
            }
        }
    }
} 