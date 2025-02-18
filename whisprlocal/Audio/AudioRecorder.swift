import Foundation
import AVFoundation
import SwiftUI

/// A singleton class to manage audio recording using AVAudioEngine.
class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()
    
    private let audioEngine = AVAudioEngine()
    
    @Published var isRecording: Bool = false
    @Published var lastError: Error? = nil
    
    private override init() {
        super.init()
        // No need for audio session setup on macOS
    }
    
    /// Starts audio capture
    func startRecording() {
        // If we're already recording, do nothing
        guard !isRecording else { return }
        
        do {
            try startEngine()
            isRecording = true
        } catch {
            lastError = error
            print("Failed to start recording: \(error)")
        }
    }
    
    /// Stops audio capture and resets the engine.
    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        // Process accumulated audio when recording stops
        Task {
            await TranscriptionManager.shared.processAccumulatedAudio()
        }
    }
    
    /// Sets up tap on the inputNode and starts the audio engine.
    private func startEngine() throws {
        let inputNode = audioEngine.inputNode
        
        // Configure format for 16kHz mono audio (optimal for Whisper)
        let desiredFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("Input format: \(recordingFormat.description)")
        print("Desired format: \(desiredFormat.description)")
        
        // Create converter if needed
        guard let converter = AVAudioConverter(from: recordingFormat, to: desiredFormat) else {
            print("Failed to create audio converter")
            return
        }
        
        // Using a smaller buffer size (0.2 seconds) for better real-time performance
        let bufferSize = AVAudioFrameCount(recordingFormat.sampleRate * 0.2)
        print("Using buffer size: \(bufferSize) frames")
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Create output buffer with appropriate size
            let ratio = desiredFormat.sampleRate / recordingFormat.sampleRate
            let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat,
                                                       frameCapacity: outputFrames) else {
                print("Failed to create converted buffer")
                return
            }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            let convertStatus = converter.convert(to: convertedBuffer,
                                                error: &error,
                                                withInputFrom: inputBlock)
            
            if let error = error {
                print("Audio conversion error: \(error)")
                return
            }
            
            if convertStatus == .error {
                print("Conversion failed with status: \(convertStatus)")
                return
            }
            
            // Add the converted buffer to the accumulator
            Task { @MainActor in
                TranscriptionManager.shared.addAudioToBuffer(convertedBuffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
} 