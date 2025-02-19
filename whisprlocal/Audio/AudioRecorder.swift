import Foundation
import AVFoundation
import SwiftUI

/// A singleton class to manage audio recording using AVAudioEngine.
class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()
    
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    
    @Published var isRecording: Bool = false
    @Published var lastError: Error? = nil
    @Published var microphonePermission: AVAuthorizationStatus = .notDetermined
    @Published private(set) var inputLevel: Float = 0.0
    
    private var levelUpdateTimer: Timer?
    
    private override init() {
        super.init()
        checkMicrophonePermission()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // Set the input volume to maximum
        inputNode.volume = 1.0
        
        // Configure the audio engine
        let mixerNode = audioEngine.mainMixerNode
        audioEngine.connect(inputNode, to: mixerNode, format: nil)
        
        // Prepare the engine
        audioEngine.prepare()
    }
    
    /// Checks and updates the current microphone permission status
    private func checkMicrophonePermission() {
        microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    /// Requests microphone permission if not already granted
    /// Returns true if permission was granted, false otherwise
    @MainActor
    func requestMicrophonePermissionIfNeeded() async -> Bool {
        // First check current status
        checkMicrophonePermission()
        
        // Return true if already authorized
        guard microphonePermission != .authorized else {
            return true
        }
        
        // Request permission
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphonePermission = granted ? .authorized : .denied
        }
        return granted
    }
    
    /// Starts audio capture
    func startRecording() {
        // If we're already recording, do nothing
        guard !isRecording else { return }
        
        // Check microphone permission first
        Task { @MainActor in
            guard await requestMicrophonePermissionIfNeeded() else {
                lastError = AudioRecorderError.microphonePermissionDenied
                return
            }
            
            do {
                try startEngine()
                isRecording = true
                startLevelMonitoring()
            } catch {
                lastError = error
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    /// Stops audio capture and resets the engine.
    func stopRecording() {
        guard isRecording else { return }
        stopLevelMonitoring()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        // Process accumulated audio when recording stops
        Task {
            await TranscriptionManager.shared.processAccumulatedAudio()
        }
    }
    
    private func startLevelMonitoring() {
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateInputLevel()
        }
    }
    
    private func stopLevelMonitoring() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        inputLevel = 0.0
    }
    
    private func updateInputLevel() {
        guard isRecording else { return }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateLevel(buffer)
            DispatchQueue.main.async {
                self.inputLevel = level
            }
            self.inputNode.removeTap(onBus: 0)
        }
    }
    
    private func calculateLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameLength = UInt32(buffer.frameLength)
        
        var sum: Float = 0
        for i in 0..<Int(frameLength) {
            let sample = abs(channelData[i])
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        return max(0.0, min(1.0, rms * 5)) // Scale RMS to 0-1 range
    }
    
    /// Sets up tap on the inputNode and starts the audio engine.
    private func startEngine() throws {
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat)")
        
        let desiredFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        print("Desired format: \(desiredFormat)")
        
        // Create converter if needed
        guard let converter = AVAudioConverter(from: inputFormat, to: desiredFormat) else {
            throw AudioRecorderError.failedToCreateConverter
        }
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Create output buffer with appropriate size
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * desiredFormat.sampleRate / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: frameCount) else {
                print("Failed to create converted buffer")
                return
            }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let error = error {
                print("Conversion error: \(error)")
                return
            }
            
            if status == .error {
                print("Conversion failed")
                return
            }
            
            // Debug audio levels
            if let data = convertedBuffer.floatChannelData?[0] {
                let frameCount = Int(convertedBuffer.frameLength)
                var sum: Float = 0
                var max: Float = 0
                for i in 0..<frameCount {
                    let sample = abs(data[i])
                    sum += sample
                    max = Swift.max(max, sample)
                }
                let avg = sum / Float(frameCount)
                print("Audio levels - Max: \(max), Avg: \(avg)")
            }
            
            Task { @MainActor in
                TranscriptionManager.shared.addAudioToBuffer(convertedBuffer)
            }
        }
        
        // Prepare and start the engine
        audioEngine.prepare()
        try audioEngine.start()
        print("Audio engine started successfully")
    }
    
    enum AudioRecorderError: LocalizedError {
        case microphonePermissionDenied
        case failedToCreateConverter
        
        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access is required for recording. Please grant permission in System Settings > Privacy & Security > Microphone."
            case .failedToCreateConverter:
                return "Failed to create audio converter. Please check your audio input device."
            }
        }
    }
} 