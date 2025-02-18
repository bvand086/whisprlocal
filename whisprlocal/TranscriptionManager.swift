import Foundation
import SwiftWhisper
import AVFoundation

struct TranscriptionEntry: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published private(set) var isModelLoaded = false
    @Published private(set) var currentError: Error?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    
    // Store recent transcriptions
    @Published private(set) var recentTranscriptions: [TranscriptionEntry] = []
    private let maxTranscriptions = 10
    
    // Buffer for current transcription
    @Published private(set) var currentBuffer: String = ""
    
    // Store partial or continuous transcription text
    @Published var transcribedText: String = ""
    
    private var whisper: Whisper?
    
    // Model management
    private let modelsFolderURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsPath = appSupport.appendingPathComponent("Whisprlocal/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)
        return modelsPath
    }()
    
    private init() {}
    
    func loadModel(named modelName: String) async throws {
        // Validate GGML model
        let ggmlModelURL = modelsFolderURL.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: ggmlModelURL.path) else {
            throw TranscriptionError.modelNotFound(type: "GGML")
        }
        
        // Validate Core ML model
        let coreMLModelURL = modelsFolderURL.appendingPathComponent("ggml-base.en-encoder.mlmodelc")
        guard FileManager.default.fileExists(atPath: coreMLModelURL.path) else {
            throw TranscriptionError.modelNotFound(type: "Core ML")
        }
        
        // Initialize Whisper with both models
        whisper = try Whisper(fromFileURL: ggmlModelURL)
        
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
    
    /// Process an audio buffer from the AudioRecorder in real-time.
    /// - Parameters:
    ///   - buffer: AVAudioPCMBuffer containing the audio samples (expected to be 16kHz mono).
    @MainActor
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isModelLoaded, let whisper = whisper else {
            print("⚠️ Model not loaded or whisper instance is nil")
            return
        }
        
        guard let channelData = buffer.floatChannelData?[0] else {
            print("⚠️ Invalid audio data: no channel data")
            currentError = TranscriptionError.invalidAudioData
            return
        }
        
        let frameCount = Int(buffer.frameLength)
        var audioData = [Float](repeating: 0, count: frameCount)
        
        // Copy and normalize audio data to [-1, 1] range
        channelData.withMemoryRebound(to: Float.self, capacity: frameCount) { ptr in
            for i in 0..<frameCount {
                // Ensure audio data is in [-1, 1] range
                audioData[i] = max(-1.0, min(1.0, ptr[i]))
            }
        }
        
        print("🎤 Processing audio buffer with \(frameCount) frames")
        
        do {
            let segments = try await whisper.transcribe(audioFrames: audioData)
            
            // Process all segments
            for segment in segments {
                let text = segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                print("🗣️ New segment: \(text)")
                
                if !text.isEmpty {
                    // Add to current buffer
                    if !currentBuffer.isEmpty {
                        currentBuffer.append(" ")
                    }
                    currentBuffer.append(text)
                    
                    // If we detect end of utterance or buffer is getting long, create new entry
                    if text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!") || currentBuffer.count > 200 {
                        print("📝 Creating new transcription entry: \(currentBuffer)")
                        addTranscriptionEntry(currentBuffer)
                        currentBuffer = ""
                    }
                }
            }
        } catch {
            print("❌ Transcription error: \(error)")
            if "\(error)".contains("instanceBusy") {
                // If instance is busy, wait a short moment and try again
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                await processAudioBuffer(buffer)
            } else {
                self.currentError = error
            }
        }
    }
    
    private func addTranscriptionEntry(_ text: String) {
        let entry = TranscriptionEntry(text: text.trimmingCharacters(in: .whitespacesAndNewlines), timestamp: Date())
        recentTranscriptions.insert(entry, at: 0)
        if recentTranscriptions.count > maxTranscriptions {
            recentTranscriptions.removeLast()
        }
    }
    
    enum TranscriptionError: LocalizedError {
        case modelNotFound(type: String)
        case downloadFailed
        case invalidAudioData
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound(let type):
                return "The \(type) model file could not be found"
            case .downloadFailed:
                return "Failed to download the model file"
            case .invalidAudioData:
                return "Invalid audio data received"
            }
        }
    }
} 
