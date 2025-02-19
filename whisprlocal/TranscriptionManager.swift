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
    private let maxBufferSize = 16000 * 120 // 120 seconds at 16kHz (increased from 30s for longer recordings)
    
    // Processing state
    @Published var isRecording = false
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
        // In SwiftWhisper 1.2.0, language selection is not supported
        // We'll keep track of the user's preference but use auto-detection
        await MainActor.run {
            currentLanguage = .auto
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
        defer { 
            isProcessing = false
            // Clear the buffer after processing, regardless of success
            audioBuffer.removeAll()
        }

        do {
            print("🎤 Processing audio buffer with \(audioBuffer.count) samples")

            // Normalize the audio buffer to [-1, 1] range
            let normalizedBuffer = audioBuffer.map { sample in
                return max(-1.0, min(1.0, sample))
            }

            // Process the entire audio buffer at once for better context
            let segments: [Segment] = try await whisper.transcribe(audioFrames: normalizedBuffer)
            
            var transcriptionText = ""
            var hasValidContent = false

            // Process the transcription segments
            for segment in segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🗣️ Segment received: \(text)")
                
                // Skip empty or noise segments
                guard !text.isEmpty && text != "[BLANK_AUDIO]" else {
                    print("⏭️ Skipping empty or blank segment")
                    continue
                }

                hasValidContent = true
                if !transcriptionText.isEmpty {
                    transcriptionText.append(" ")
                }
                transcriptionText.append(text)
            }

            // Only add to history if we have valid content
            if hasValidContent {
                print("📝 Adding transcription: \(transcriptionText)")
                addTranscriptionEntry(transcriptionText)
                transcribedText = transcriptionText
            } else {
                print("ℹ️ No valid speech content detected")
                transcribedText = ""
            }

        } catch {
            print("❌ Transcription error: \(error)")
            currentError = error
            transcribedText = ""
        }
    }
    
    /// Clear the current audio buffer without processing
    func clearAudioBuffer() {
        audioBuffer.removeAll()
    }
    
    private func addTranscriptionEntry(_ text: String) {
        let entry = TranscriptionEntry(text: text, timestamp: Date())
        
        // Insert at the beginning of the array (most recent first)
        recentTranscriptions.insert(entry, at: 0)
        
        // Keep only the most recent transcriptions
        if recentTranscriptions.count > maxTranscriptions {
            recentTranscriptions.removeLast()
        }
        
        print("📋 Updated transcription history (count: \(recentTranscriptions.count))")
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

