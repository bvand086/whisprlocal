import Foundation
import SwiftWhisper
import AVFoundation
import AppKit

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
    
    // Real-time transcription update handler
    var onTranscriptionUpdate: ((String) -> Void)?
    
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
    
    // Audio visualization
    @Published private(set) var audioLevels: [Float] = []
    private let maxAudioLevels = 50
    private let audioLevelUpdateInterval: TimeInterval = 1/30 // 30fps
    private var audioLevelTimer: Timer?
    
    // Add a prompt property to the class properties section
    @Published var promptText: String = ""
    
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
        print("🔍 Loading model from: \(ggmlModelURL.path)")
        
        guard FileManager.default.fileExists(atPath: ggmlModelURL.path) else {
            print("❌ Model file not found at: \(ggmlModelURL.path)")
            throw TranscriptionError.modelNotFound(type: "GGML")
        }
        
        // Get the correct CoreML model name and path
        let coreMLModelName = ModelManager.getCoreMLModelName(for: modelName)
        let coreMLModelURL = modelsFolderURL.appendingPathComponent(coreMLModelName)
        
        if FileManager.default.fileExists(atPath: coreMLModelURL.path) {
            print("✅ Found CoreML model: \(coreMLModelName)")
            setenv("WHISPER_COREML_MODEL_PATH", coreMLModelURL.path, 1)
        } else {
            print("⚠️ CoreML model not found, will use CPU-only mode")
            unsetenv("WHISPER_COREML_MODEL_PATH")
        }
        
        // Save the model name for future reloads (e.g. when changing language)
        currentModelName = modelName
        
        print("🚀 Initializing Whisper with model: \(modelName)")
        
        // Initialize model in an autorelease pool with proper error handling
        let whisperInstance = try await Task.detached(priority: .userInitiated) { () -> Whisper? in
            do {
                return try autoreleasepool { () throws -> Whisper? in
                    let instance = try Whisper(fromFileURL: ggmlModelURL)
                    if instance == nil {
                        throw TranscriptionError.modelInitializationFailed
                    }
                    return instance
                }
            } catch {
                print("❌ Failed to initialize Whisper: \(error)")
                throw error
            }
        }.value
        
        guard let whisperInstance = whisperInstance else {
            print("❌ Whisper initialization returned nil")
            throw TranscriptionError.modelInitializationFailed
        }
        
        // Add a small delay to allow memory to stabilize
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        
        self.whisper = whisperInstance
        
        await MainActor.run {
            isModelLoaded = true
            currentError = nil
            print("✅ Model loaded successfully" + (FileManager.default.fileExists(atPath: coreMLModelURL.path) ? " with CoreML support" : " in CPU-only mode"))
        }
    }
    
    func unloadCurrentModel() async throws {
        print("🗑️ Unloading current model")
        await MainActor.run {
            whisper = nil
            isModelLoaded = false
            currentModelName = nil
        }
        
        // Force multiple cleanup cycles
        print("♻️ Triggering aggressive memory cleanup")
        for _ in 0..<3 {
            _ = autoreleasepool { () -> Bool in
                // Empty autorelease pool to help with memory cleanup
                return true
            }
        }
        
        // Add a small delay to allow memory to be properly released
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
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
        
        // Calculate RMS value for this buffer
        var sumSquares: Float = 0.0
        channelData.withMemoryRebound(to: Float.self, capacity: frameCount) { ptr in
            for i in 0..<frameCount {
                let sample = max(-1.0, min(1.0, ptr[i]))
                sumSquares += sample * sample
                audioBuffer.append(sample)
            }
        }
        
        let rms = sqrt(sumSquares / Float(frameCount))
        // Normalize RMS to 0-1 range with some headroom
        let normalizedLevel = min(rms * 4, 1.0)
        
        // Update audio levels array
        audioLevels.append(normalizedLevel)
        if audioLevels.count > maxAudioLevels {
            audioLevels.removeFirst()
        }
        
        // If buffer gets too large, remove oldest data
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(frameCount)
        }
    }
    
    /// Process all accumulated audio data
    @MainActor
    func processAccumulatedAudio() async {
        guard !audioBuffer.isEmpty else {
            print("⚠️ Audio buffer is empty")
            return
        }
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
            print("🎤 Processing audio buffer:")
            print("  Buffer size: \(audioBuffer.count) samples")
            
            // Calculate audio statistics before normalization
            let stats = calculateAudioStats(audioBuffer)
            print("  Pre-normalization stats:")
            print("    Min: \(stats.min), Max: \(stats.max)")
            print("    Average magnitude: \(stats.avgMagnitude)")
            print("    RMS: \(stats.rms)")

            // Normalize the audio buffer to [-1, 1] range
            let normalizedBuffer = audioBuffer.map { sample in
                return max(-1.0, min(1.0, sample))
            }
            
            // Calculate normalized stats
            let normalizedStats = calculateAudioStats(normalizedBuffer)
            print("  Post-normalization stats:")
            print("    Min: \(normalizedStats.min), Max: \(normalizedStats.max)")
            print("    Average magnitude: \(normalizedStats.avgMagnitude)")
            print("    RMS: \(normalizedStats.rms)")

            print("🔄 Starting transcription...")
            
            // Set prompt if available
            if !promptText.isEmpty {
                print("🔤 Using prompt: \"\(promptText)\"")
                // Use environment variable to pass prompt to whisper.cpp
                setenv("WHISPER_PROMPT", promptText, 1)
            } else {
                unsetenv("WHISPER_PROMPT")
            }
            
            let segments = try await whisper.transcribe(audioFrames: audioBuffer)
            
            // Process segments and build final transcription
            let transcriptionText = segments.map { $0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            let hasValidContent = !transcriptionText.isEmpty
            
            if hasValidContent {
                print("📝 Final transcription: '\(transcriptionText)'")
                addTranscriptionEntry(transcriptionText)
                transcribedText = transcriptionText
                
                await MainActor.run {
                    // Update the clipboard with the transcribed text
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(transcriptionText, forType: .string)
                    
                    // Notify any real-time update handlers
                    onTranscriptionUpdate?(transcriptionText)
                    
                    // Simulate a paste command to insert the transcribed text
                    Paster.pasteText()
                }
            } else {
                print("ℹ️ No valid speech content detected in any segments")
                transcribedText = ""
            }

        } catch {
            print("❌ Transcription error: \(error)")
            currentError = error
            transcribedText = ""
        }
    }
    
    /// Calculate audio statistics for debugging
    private func calculateAudioStats(_ buffer: [Float]) -> (min: Float, max: Float, avgMagnitude: Float, rms: Float) {
        guard !buffer.isEmpty else { return (0, 0, 0, 0) }
        
        var min: Float = buffer[0]
        var max: Float = buffer[0]
        var sum: Float = 0
        var sumSquares: Float = 0
        
        for sample in buffer {
            min = Swift.min(min, sample)
            max = Swift.max(max, sample)
            sum += abs(sample)
            sumSquares += sample * sample
        }
        
        let avgMagnitude = sum / Float(buffer.count)
        let rms = sqrt(sumSquares / Float(buffer.count))
        
        return (min, max, avgMagnitude, rms)
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
        
        // Add to clipboard history
        ClipboardManager.shared.addToHistory(text: text, type: .transcription)
        
        print("📋 Updated transcription history (count: \(recentTranscriptions.count))")
    }
    
    func startRecording() {
        isRecording = true
        // Start audio level timer
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: audioLevelUpdateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // If no new audio data, add a zero level
            if self.audioLevels.count < self.maxAudioLevels {
                self.audioLevels.append(0)
            }
        }
    }
    
    func stopRecording() {
        isRecording = false
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        // Clear audio levels
        audioLevels.removeAll()
    }
    
    enum TranscriptionError: LocalizedError {
        case modelNotFound(type: String)
        case downloadFailed
        case invalidAudioData
        case modelInitializationFailed
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound(let type):
                return "The \(type) model file could not be found"
            case .downloadFailed:
                return "Failed to download the model file"
            case .invalidAudioData:
                return "Invalid audio data received"
            case .modelInitializationFailed:
                return "Failed to initialize the model"
            }
        }
    }
} 

