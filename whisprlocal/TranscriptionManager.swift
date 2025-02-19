import Foundation
import SwiftWhisper
import AVFoundation

// Define WhisperLanguage enum
public enum WhisperLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case chinese = "zh"
    case german = "de"
    case spanish = "es"
    case russian = "ru"
    case korean = "ko"
    case french = "fr"
    case japanese = "ja"
    case portuguese = "pt"
    case turkish = "tr"
    case polish = "pl"
    case catalan = "ca"
    case dutch = "nl"
    case arabic = "ar"
    case swedish = "sv"
    case italian = "it"
    case indonesian = "id"
    case hindi = "hi"
    case finnish = "fi"
    case vietnamese = "vi"
    case hebrew = "iw"
    case ukrainian = "uk"
    case greek = "el"
    case malay = "ms"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto Detect"
        default: return rawValue.uppercased()
        }
    }
}

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
    @Published private(set) var isProcessing = false
    @Published var currentLanguage: WhisperLanguage = .english
    
    // Store the name of the currently loaded model so that it can be reloaded with a new language.
    private var currentModelName: String?
    
    // Store recent transcriptions
    @Published private(set) var recentTranscriptions: [TranscriptionEntry] = []
    private let maxTranscriptions = 10
    
    // Buffer for audio data
    private var audioBuffer: [Float] = []
    private let maxBufferSize = 16000 * 30 // 30 seconds at 16kHz
    
    // Store partial or continuous transcription text
    @Published var transcribedText: String = ""
    
    private var whisper: Whisper?
    
    // Add a serial queue for audio processing
    private let processingQueue = DispatchQueue(label: "com.whisprlocal.audioProcessing")
    private let maxRetries = 3
    private let retryDelay: UInt64 = 500_000_000 // 500ms
    
    // Model management
    private let modelsFolderURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsPath = appSupport.appendingPathComponent("Whisprlocal/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)
        return modelsPath
    }()
    
    private init() {}
    
    func setLanguage(_ language: WhisperLanguage) async throws {
        currentLanguage = language
        
        if isModelLoaded, let modelName = currentModelName {
            try await loadModel(named: modelName)
        }
    }
    
    func loadModel(named modelName: String) async throws {
        let ggmlModelURL = modelsFolderURL.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: ggmlModelURL.path) else {
            throw TranscriptionError.modelNotFound(type: "GGML")
        }
        
        // Save the model name for future reloads (e.g. when changing language)
        currentModelName = modelName
        
        // Initialize Whisper with only the file URL
        whisper = Whisper(fromFileURL: ggmlModelURL)
        
        await MainActor.run {
            isModelLoaded = true
            currentError = nil  // Clear any previous errors
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
    
    /// Add audio data to the buffer for later processing
    /// - Parameter buffer: AVAudioPCMBuffer containing the audio samples (expected to be 16kHz mono)
    @MainActor
    func addAudioToBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            print("⚠️ Invalid audio data: no channel data")
            currentError = TranscriptionError.invalidAudioData
            return
        }
        
        let frameCount = Int(buffer.frameLength)
        
        // Copy and normalize audio data to [-1, 1] range
        channelData.withMemoryRebound(to: Float.self, capacity: frameCount) { ptr in
            for i in 0..<frameCount {
                let sample = max(-1.0, min(1.0, ptr[i]))
                audioBuffer.append(sample)
            }
        }
        
        // If buffer gets too large, remove oldest data
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(frameCount)
        }
    }
    
    /// Process all accumulated audio data
    @MainActor
    func processAccumulatedAudio() async {
        guard !audioBuffer.isEmpty else { return }
        guard isModelLoaded, let whisper = whisper else {
            print("⚠️ Model not loaded or whisper instance is nil")
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            print("🎤 Processing audio buffer with \(audioBuffer.count) samples")
            
            // Normalize the audio buffer
            let normalizedBuffer = audioBuffer.map { sample in
                return max(-1.0, min(1.0, sample))
            }
            
            // SwiftWhisper version in use does not support the language parameter.
            // If a forced language is desired, show a warning and proceed with auto-detection.
            if currentLanguage != .auto {
                print("⚠️ Warning: Forced language transcription is not supported in the current SwiftWhisper version. Using auto-detection instead.")
            }
            
            let segments: [Segment] = try await whisper.transcribe(audioFrames: normalizedBuffer)
            
            var transcriptionText = ""
            
            // Process the transcription segments
            for segment in segments {
                let text = segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                print("🗣️ New segment: \(text)")
                if !text.isEmpty && text != "[BLANK_AUDIO]" {
                    if !transcriptionText.isEmpty {
                        transcriptionText.append(" ")
                    }
                    transcriptionText.append(text)
                }
            }
            
            if !transcriptionText.isEmpty {
                print("📝 Adding transcription: \(transcriptionText)")
                addTranscriptionEntry(transcriptionText)
            }
            
            // Clear the buffer after successful processing
            audioBuffer.removeAll()
            
        } catch {
            print("❌ Transcription error: \(error)")
            currentError = error
        }
    }
    
    /// Clear the current audio buffer without processing
    func clearAudioBuffer() {
        audioBuffer.removeAll()
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

