import Foundation
import SwiftWhisper
import AVFoundation

class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published private(set) var isModelLoaded = false
    @Published private(set) var currentError: Error?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    
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
        let modelURL = modelsFolderURL.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelNotFound
        }
        
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
        guard isModelLoaded, let whisper = whisper else { return }
        
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameCount = Int(buffer.frameLength)
        var audioData = [Float](repeating: 0, count: frameCount)
        
        // Copy the audio data into our array
        channelData.withMemoryRebound(to: Float.self, capacity: frameCount) { ptr in
            audioData.withUnsafeMutableBufferPointer { bufferPtr in
                bufferPtr.baseAddress?.initialize(from: ptr, count: frameCount)
            }
        }
        
        do {
            // Transcribe the audio data
            let segments = try await whisper.transcribe(audioFrames: audioData)
            
            // Combine all text segments
            let combinedText = segments.map { $0.text }.joined(separator: " ")
            
            // Append to our transcribed text
            if !combinedText.isEmpty {
                self.transcribedText.append(contentsOf: " " + combinedText)
            }
        } catch {
            self.currentError = error
        }
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